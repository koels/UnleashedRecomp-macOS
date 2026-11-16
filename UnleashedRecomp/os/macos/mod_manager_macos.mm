#include "mod_manager_macos.h"
#include "menu_macos.h"

#import <AppKit/AppKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>
#include <user/paths.h>

// Hedge Mod Manager-format mods (folders with a mod.ini) in <user>/mods. Order and enabled state go
// to mods/ModsDB.ini, which cpkredir.ini points the game's mod loader at; the top of the list wins.

namespace fs = std::filesystem;

static fs::path ModsDirectory() { return GetUserPath() / "mods"; }
static fs::path ModsDbPath() { return ModsDirectory() / "ModsDB.ini"; }
static fs::path CpkRedirPath() { return GetUserPath() / "cpkredir.ini"; }

static NSString* ToNS(const std::string& string) { return @(string.c_str()) ?: @""; }
static NSString* ToNS(const fs::path& path) { return ToNS(path.string()); }

struct IniEntry
{
    std::string section;
    std::string key;
    std::string value;
};

// Tiny reader that keeps file order, which the load order depends on.
static std::vector<IniEntry> ReadIni(const fs::path& path)
{
    std::vector<IniEntry> entries;
    std::ifstream file(path);
    std::string line, section;

    while (std::getline(file, line))
    {
        if (!line.empty() && line.back() == '\r')
            line.pop_back();

        if (line.starts_with('['))
        {
            section = line.substr(1, line.find(']') - 1);
            continue;
        }

        auto equals = line.find('=');
        if (equals == std::string::npos || line.starts_with(';'))
            continue;

        auto unquote = [](std::string text)
        {
            return text.size() >= 2 && text.front() == '"' && text.back() == '"' ? text.substr(1, text.size() - 2) : text;
        };

        entries.push_back({ section, unquote(line.substr(0, equals)), unquote(line.substr(equals + 1)) });
    }

    return entries;
}

static std::string FindIniValue(const std::vector<IniEntry>& entries, std::string_view section, std::string_view key)
{
    for (auto& entry : entries)
    {
        if (entry.section == section && entry.key == key)
            return entry.value;
    }

    return {};
}

@interface ModItem : NSObject
@property NSString* modId;
@property NSString* iniPath;
@property NSString* title;
@property NSString* version;
@property NSString* author;
@property BOOL isEnabled;
@end

@implementation ModItem
@end

static ModItem* LoadModItem(const fs::path& iniPath)
{
    auto ini = ReadIni(iniPath);
    auto title = FindIniValue(ini, "Desc", "Title");

    ModItem* item = [ModItem new];
    item.modId = ToNS(iniPath.parent_path().filename());
    item.iniPath = ToNS(iniPath);
    item.title = title.empty() ? item.modId : ToNS(title);
    item.version = ToNS(FindIniValue(ini, "Desc", "Version"));
    item.author = ToNS(FindIniValue(ini, "Desc", "Author"));
    return item;
}

// Shallowest mod.ini inside a folder, so archives with a wrapper folder still install.
static fs::path FindModIni(const fs::path& root)
{
    std::error_code ec;

    if (fs::exists(root / "mod.ini", ec))
        return root / "mod.ini";

    for (auto it = fs::recursive_directory_iterator(root, ec); it != fs::recursive_directory_iterator(); it.increment(ec))
    {
        if (it.depth() < 3 && it->path().filename() == "mod.ini")
            return it->path();
    }

    return {};
}

static fs::path UniqueDestination(const std::string& name)
{
    auto destination = ModsDirectory() / name;

    for (int i = 2; fs::exists(destination); i++)
        destination = ModsDirectory() / (name + " " + std::to_string(i));

    return destination;
}

static NSPasteboardType const ModRowType = @"io.github.koels.UnleashedRecomp.mod-row";

@interface ModManagerController : NSObject <NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate>
@property NSWindow* window;
@property NSTableView* table;
@property NSTextField* status;
@property NSButton* restartButton;
@property NSMutableArray<ModItem*>* mods;
@end

@implementation ModManagerController

- (void)loadMods
{
    std::error_code ec;
    fs::create_directories(ModsDirectory(), ec);

    NSMutableDictionary<NSString*, ModItem*>* installed = [NSMutableDictionary dictionary];
    for (auto& entry : fs::directory_iterator(ModsDirectory(), ec))
    {
        if (entry.is_directory() && fs::exists(entry.path() / "mod.ini"))
        {
            ModItem* item = LoadModItem(entry.path() / "mod.ini");
            installed[item.modId] = item;
        }
    }

    // Saved order and enabled state; mods installed by hand go to the bottom, off.
    auto db = ReadIni(ModsDbPath());
    NSMutableSet<NSString*>* enabled = [NSMutableSet set];
    for (auto& entry : db)
    {
        if (entry.section == "Main" && entry.key.starts_with("ActiveMod") && entry.key != "ActiveModCount")
            [enabled addObject:ToNS(entry.value)];
    }

    self.mods = [NSMutableArray array];
    for (auto& entry : db)
    {
        ModItem* item = entry.section == "Mods" ? installed[ToNS(entry.key)] : nil;
        if (item)
        {
            item.isEnabled = [enabled containsObject:item.modId];
            [self.mods addObject:item];
            [installed removeObjectForKey:item.modId];
        }
    }

    for (NSString* modId in [installed.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)])
        [self.mods addObject:installed[modId]];

    [self.table reloadData];
}

- (void)saveMods
{
    std::ofstream db(ModsDbPath());
    std::vector<ModItem*> active;

    for (ModItem* item in self.mods)
    {
        if (item.isEnabled)
            active.push_back(item);
    }

    db << "[Main]\nActiveModCount=" << active.size() << "\n";
    for (size_t i = 0; i < active.size(); i++)
        db << "ActiveMod" << i << "=\"" << active[i].modId.UTF8String << "\"\n";

    db << "\n[Mods]\n";
    // Keys are quoted: the game's INI reader ends unquoted keys at the first space.
    for (ModItem* item in self.mods)
        db << '"' << item.modId.UTF8String << "\"=\"" << item.iniPath.UTF8String << "\"\n";

    std::ofstream cpkRedir(CpkRedirPath());
    cpkRedir << "[CPKREDIR]\nEnabled=1\nModsDbIni=\"" << ModsDbPath().string() << "\"\n";

    self.status.stringValue = @"Changes take effect after the game restarts.";
    self.restartButton.hidden = NO;
}

- (void)install:(id)sender
{
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.message = @"Choose mod .zip files or folders. Each mod needs a mod.ini (Hedge Mod Manager format).";
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = YES;
    panel.allowedContentTypes = @[ UTTypeZIP, UTTypeFolder ];

    if ([panel runModal] != NSModalResponseOK)
        return;

    NSMutableArray<NSString*>* failed = [NSMutableArray array];

    for (NSURL* url in panel.URLs)
    {
        fs::path source = url.fileSystemRepresentation;
        fs::path extracted;
        std::error_code ec;

        if ([url.pathExtension caseInsensitiveCompare:@"zip"] == NSOrderedSame)
        {
            extracted = fs::temp_directory_path() / ("UnleashedRecompMod-" + std::string(NSUUID.UUID.UUIDString.UTF8String));
            NSTask* task = [NSTask launchedTaskWithExecutableURL:[NSURL fileURLWithPath:@"/usr/bin/ditto"]
                arguments:@[ @"-x", @"-k", url.path, ToNS(extracted) ] error:nil terminationHandler:nil];
            [task waitUntilExit];
            source = extracted;
        }

        auto modIni = FindModIni(source);
        if (modIni.empty())
        {
            [failed addObject:url.lastPathComponent];
        }
        else
        {
            // A mod.ini at the top of an archive has no folder name of its own; use the archive's.
            auto modRoot = modIni.parent_path();
            auto name = modRoot == extracted ? std::string(url.URLByDeletingPathExtension.lastPathComponent.UTF8String) : modRoot.filename().string();
            auto destination = UniqueDestination(name);

            if (extracted.empty())
                fs::copy(modRoot, destination, fs::copy_options::recursive, ec);
            else
                fs::rename(modRoot, destination, ec);

            if (ec)
            {
                [failed addObject:url.lastPathComponent];
            }
            else
            {
                ModItem* item = LoadModItem(destination / "mod.ini");
                item.isEnabled = YES;
                [self.mods insertObject:item atIndex:0];
            }
        }

        if (!extracted.empty())
            fs::remove_all(extracted, ec);
    }

    [self.table reloadData];
    [self saveMods];

    if (failed.count)
    {
        NSAlert* alert = [NSAlert new];
        alert.messageText = @"Some mods couldn't be installed.";
        alert.informativeText = [NSString stringWithFormat:@"No mod.ini was found in: %@\n\nOnly Hedge Mod Manager-format mods in a .zip or folder are supported.", [failed componentsJoinedByString:@", "]];
        [alert runModal];
    }
}

- (void)remove:(id)sender
{
    NSInteger row = self.table.selectedRow;
    if (row < 0)
        return;

    ModItem* item = self.mods[row];

    NSAlert* alert = [NSAlert new];
    alert.messageText = [NSString stringWithFormat:@"Remove “%@”?", item.title];
    alert.informativeText = @"The mod's folder is moved to the Trash.";
    [alert addButtonWithTitle:@"Move to Trash"];
    [alert addButtonWithTitle:@"Cancel"];

    if ([alert runModal] != NSAlertFirstButtonReturn)
        return;

    NSURL* folder = [NSURL fileURLWithPath:item.iniPath].URLByDeletingLastPathComponent;
    [NSFileManager.defaultManager trashItemAtURL:folder resultingItemURL:nil error:nil];

    [self.mods removeObjectAtIndex:row];
    [self.table reloadData];
    [self saveMods];
}

- (void)showInFinder:(id)sender
{
    NSInteger row = self.table.selectedRow;
    NSURL* url = row >= 0
        ? [NSURL fileURLWithPath:self.mods[row].iniPath].URLByDeletingLastPathComponent
        : [NSURL fileURLWithPath:ToNS(ModsDirectory())];

    [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[ url ]];
}

- (void)restart:(id)sender
{
    os::macos::RestartGame();
}

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView
{
    return self.mods.count;
}

- (id)tableView:(NSTableView*)tableView objectValueForTableColumn:(NSTableColumn*)column row:(NSInteger)row
{
    ModItem* item = self.mods[row];

    if ([column.identifier isEqualToString:@"enabled"])
        return @(item.isEnabled);

    return [item valueForKey:column.identifier];
}

- (void)tableView:(NSTableView*)tableView setObjectValue:(id)value forTableColumn:(NSTableColumn*)column row:(NSInteger)row
{
    self.mods[row].isEnabled = [value boolValue];
    [self saveMods];
}

- (id<NSPasteboardWriting>)tableView:(NSTableView*)tableView pasteboardWriterForRow:(NSInteger)row
{
    NSPasteboardItem* item = [NSPasteboardItem new];
    [item setString:@(row).stringValue forType:ModRowType];
    return item;
}

- (NSDragOperation)tableView:(NSTableView*)tableView validateDrop:(id<NSDraggingInfo>)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)operation
{
    [tableView setDropRow:row dropOperation:NSTableViewDropAbove];
    return NSDragOperationMove;
}

- (BOOL)tableView:(NSTableView*)tableView acceptDrop:(id<NSDraggingInfo>)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)operation
{
    NSInteger from = [[info.draggingPasteboard stringForType:ModRowType] integerValue];
    ModItem* item = self.mods[from];

    [self.mods removeObjectAtIndex:from];
    [self.mods insertObject:item atIndex:from < row ? row - 1 : row];

    [tableView reloadData];
    [self saveMods];
    return YES;
}

- (NSButton*)buttonWithTitle:(NSString*)title action:(SEL)action
{
    NSButton* button = [NSButton buttonWithTitle:title target:self action:action];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    return button;
}

- (void)buildWindow
{
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 420)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"Mods";
    self.window.releasedWhenClosed = NO;
    self.window.minSize = NSMakeSize(480, 300);

    // Shows over the game in fullscreen too.
    self.window.level = NSFloatingWindowLevel;
    self.window.collectionBehavior = NSWindowCollectionBehaviorFullScreenAuxiliary | NSWindowCollectionBehaviorMoveToActiveSpace;

    self.table = [NSTableView new];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.usesAlternatingRowBackgroundColors = YES;
    [self.table registerForDraggedTypes:@[ ModRowType ]];

    NSArray* columns = @[ @[ @"enabled", @"", @24 ], @[ @"title", @"Mod", @300 ], @[ @"version", @"Version", @80 ], @[ @"author", @"Author", @160 ] ];
    for (NSArray* spec in columns)
    {
        NSTableColumn* column = [[NSTableColumn alloc] initWithIdentifier:spec[0]];
        column.title = spec[1];
        column.width = [spec[2] doubleValue];
        column.editable = [spec[0] isEqualToString:@"enabled"];

        if (column.editable)
        {
            NSButtonCell* checkbox = [NSButtonCell new];
            checkbox.buttonType = NSButtonTypeSwitch;
            checkbox.title = @"";
            column.dataCell = checkbox;
        }

        [self.table addTableColumn:column];
    }

    NSScrollView* scroll = [NSScrollView new];
    scroll.documentView = self.table;
    scroll.hasVerticalScroller = YES;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField* hint = [NSTextField labelWithString:@"Check a mod to turn it on. Drag to reorder: mods higher in the list win when they change the same files."];
    hint.textColor = NSColor.secondaryLabelColor;
    hint.translatesAutoresizingMaskIntoConstraints = NO;

    self.status = [NSTextField labelWithString:@""];
    self.status.translatesAutoresizingMaskIntoConstraints = NO;

    self.restartButton = [self buttonWithTitle:@"Restart Game" action:@selector(restart:)];
    self.restartButton.hidden = YES;

    NSStackView* buttons = [NSStackView stackViewWithViews:@[
        [self buttonWithTitle:@"Install Mod…" action:@selector(install:)],
        [self buttonWithTitle:@"Remove" action:@selector(remove:)],
        [self buttonWithTitle:@"Show in Finder" action:@selector(showInFinder:)],
        self.status,
        self.restartButton
    ]];
    buttons.translatesAutoresizingMaskIntoConstraints = NO;
    [buttons setCustomSpacing:16 afterView:buttons.views[2]];

    NSView* content = self.window.contentView;
    [content addSubview:hint];
    [content addSubview:scroll];
    [content addSubview:buttons];

    [NSLayoutConstraint activateConstraints:@[
        [hint.topAnchor constraintEqualToAnchor:content.topAnchor constant:12],
        [hint.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
        [hint.trailingAnchor constraintLessThanOrEqualToAnchor:content.trailingAnchor constant:-16],
        [scroll.topAnchor constraintEqualToAnchor:hint.bottomAnchor constant:8],
        [scroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
        [scroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],
        [buttons.topAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:12],
        [buttons.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
        [buttons.trailingAnchor constraintLessThanOrEqualToAnchor:content.trailingAnchor constant:-16],
        [buttons.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-14]
    ]];

    [self.window center];
}

@end

static ModManagerController* g_controller;

void os::macos::ShowModManager()
{
    // Another mod manager (e.g. Hedge Mod Manager in CrossOver) may already own cpkredir.ini.
    auto modsDb = FindIniValue(ReadIni(CpkRedirPath()), "CPKREDIR", "ModsDbIni");
    if (!g_controller && !modsDb.empty() && fs::path(modsDb) != ModsDbPath())
    {
        NSAlert* alert = [NSAlert new];
        alert.messageText = @"Mods are set up by another mod manager.";
        alert.informativeText = @"Changing mods here replaces that setup, and mods installed through it won't be listed.";
        [alert addButtonWithTitle:@"Continue"];
        [alert addButtonWithTitle:@"Cancel"];

        if ([alert runModal] != NSAlertFirstButtonReturn)
            return;
    }

    if (!g_controller)
    {
        g_controller = [ModManagerController new];
        [g_controller buildWindow];
    }

    [g_controller loadMods];
    [NSApp activateIgnoringOtherApps:YES];
    [g_controller.window makeKeyAndOrderFront:nil];
}
