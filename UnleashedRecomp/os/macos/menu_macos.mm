#include "menu_macos.h"
#include "mod_manager_macos.h"

#import <AppKit/AppKit.h>
#include <install/update_checker.h>
#include <user/config.h>
#include <user/paths.h>
#include <version.h>
#include <sys/sysctl.h>
#include <string>

static NSURL* ToURL(const std::filesystem::path& path)
{
    return [NSURL fileURLWithPath:[NSString stringWithUTF8String:path.c_str()]];
}

// Selects the file in Finder, or opens the nearest folder that exists.
static void RevealInFinder(std::filesystem::path path)
{
    std::error_code ec;

    if (std::filesystem::is_regular_file(path, ec))
    {
        [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[ ToURL(path) ]];
        return;
    }

    while (!path.empty() && !std::filesystem::is_directory(path, ec))
        path = path.parent_path();

    [NSWorkspace.sharedWorkspace openURL:ToURL(path.empty() ? GetUserPath() : path)];
}

static std::string GetSysctlString(const char* name)
{
    char buffer[256]{};
    size_t size = sizeof(buffer);
    return sysctlbyname(name, buffer, &size, nullptr, 0) == 0 ? buffer : "";
}

// Opens a new GitHub issue with the report sections and this Mac's specs already filled in.
static void OpenBugReport()
{
    uint64_t memory = 0;
    size_t size = sizeof(memory);
    sysctlbyname("hw.memsize", &memory, &size, nullptr, 0);

    auto chip = GetSysctlString("machdep.cpu.brand_string");
    auto os = std::string("macOS ") + NSProcessInfo.processInfo.operatingSystemVersionString.UTF8String;

    std::string codes;
    for (auto def : g_configDefinitions)
    {
        if (def->GetSection() == "Codes" && !def->IsHidden() && *(const bool*)def->GetValue())
            codes += "- " + std::string(def->GetName()) + "\n";
    }

    // GitHub's issue page doesn't fill issue-form fields from the link, but it does fill a
    // plain issue's body, so the report follows the bug report template's sections as text.
    std::string body =
        "### Describe the Bug\n\n\n\n"
        "### Steps to Reproduce\n\n1. \n\n"
        "### Expected Behavior\n\n\n\n"
        "### Footage\n\nAttach a screenshot or video (F12 or Cmd+Shift+S saves one to Pictures).\n\n"
        "### Mods\n\nNone\n\n"
        "### Tweaks\n\n" + (codes.empty() ? std::string("None\n") : codes) + "\n"
        "### Specs\n\n"
        "- **Version:** " + g_versionString + "\n"
        "- **Chip:** " + chip + "\n"
        "- **Memory:** " + std::to_string(memory >> 30) + " GB\n"
        "- **OS:** " + os + "\n";

    NSURLComponents* url = [NSURLComponents componentsWithString:@"https://github.com/koels/UnleashedRecomp-macOS/issues/new"];
    url.queryItems = @[ [NSURLQueryItem queryItemWithName:@"body" value:@(body.c_str())] ];

    [NSWorkspace.sharedWorkspace openURL:url.URL];
}

@interface AppMenuTarget : NSObject
@end

@implementation AppMenuTarget

- (void)checkForUpdates:(id)sender
{
    UpdateChecker::checkFromMenu();
}

- (void)showSaveFolder:(id)sender
{
    RevealInFinder(GetSaveFilePath(true));
}

- (void)showConfigFile:(id)sender
{
    RevealInFinder(Config::GetConfigPath());
}

- (void)reportBug:(id)sender
{
    OpenBugReport();
}

- (void)showMods:(id)sender
{
    os::macos::ShowModManager();
}

- (void)openSettings:(id)sender
{
    os::macos::RequestOptionsMenu();
}

@end

static AppMenuTarget* g_appMenuTarget;

void os::macos::AddAppMenuItems()
{
    NSMenu* appMenu = NSApp.mainMenu.itemArray.firstObject.submenu;

    if (!appMenu || g_appMenuTarget)
        return;

    g_appMenuTarget = [AppMenuTarget new];

    auto addItem = [&](NSString* title, SEL action, NSInteger index)
    {
        NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
        item.target = g_appMenuTarget;
        [appMenu insertItem:item atIndex:index];
    };

    // Below "About", as in other Mac apps.
    addItem(@"Check for Updates…", @selector(checkForUpdates:), 1);
    [appMenu insertItem:NSMenuItem.separatorItem atIndex:2];
    addItem(@"Mods\u2026", @selector(showMods:), 3);
    addItem(@"Show Save Folder in Finder", @selector(showSaveFolder:), 4);
    addItem(@"Show Config File in Finder", @selector(showConfigFile:), 5);
    addItem(@"Report a Bug\u2026", @selector(reportBug:), 6);

    // SDL adds Settings... (Cmd+,) with no action; make it open the game's Options.
    for (NSMenuItem* item in appMenu.itemArray)
    {
        if ([item.keyEquivalent isEqualToString:@","])
        {
            item.target = g_appMenuTarget;
            item.action = @selector(openSettings:);
        }
    }
}
