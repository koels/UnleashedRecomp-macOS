#include "update_checker.h"

#import <Sparkle/Sparkle.h>

#include <os/logger.h>

// UpdateChecker backed by Sparkle. The title screen asks check() for the result of a silent
// background probe, and visitWebsite() hands over to Sparkle's own download and install flow.

static std::atomic<UpdateChecker::Result> g_result = UpdateChecker::Result::NotStarted;

@interface UpdateCheckerDelegate : NSObject <SPUUpdaterDelegate>
@end

@implementation UpdateCheckerDelegate

- (void)updater:(SPUUpdater *)updater didFindValidUpdate:(SUAppcastItem *)item
{
    LOGF_IMPL(Utility, "Sparkle", "Update available: {}", item.displayVersionString.UTF8String);
    g_result = UpdateChecker::Result::UpdateAvailable;
}

- (void)updaterDidNotFindUpdate:(SPUUpdater *)updater error:(NSError *)error
{
    g_result = UpdateChecker::Result::AlreadyUpToDate;
}

- (void)updater:(SPUUpdater *)updater didAbortWithError:(NSError *)error
{
    // Also reported after "no update found", so only treat it as a failure if nothing else was.
    if (g_result == UpdateChecker::Result::InProgress)
    {
        LOGF_IMPL(Utility, "Sparkle", "Update check failed: {}", error.localizedDescription.UTF8String);
        g_result = UpdateChecker::Result::Failed;
    }
}

@end

static SPUUpdater* g_updater;
static UpdateCheckerDelegate* g_delegate;

void UpdateChecker::initialize()
{
    // Builds without a feed or signing key (e.g. local development) don't check for updates.
    NSDictionary* info = NSBundle.mainBundle.infoDictionary;
    if ([info[@"SUFeedURL"] length] == 0 || [info[@"SUPublicEDKey"] length] == 0)
    {
        LOG_IMPL(Utility, "Sparkle", "No SUFeedURL or SUPublicEDKey in Info.plist; update checks disabled.");
        return;
    }

    g_delegate = [UpdateCheckerDelegate new];

    auto userDriver = [[SPUStandardUserDriver alloc] initWithHostBundle:NSBundle.mainBundle delegate:nil];
    g_updater = [[SPUUpdater alloc] initWithHostBundle:NSBundle.mainBundle applicationBundle:NSBundle.mainBundle userDriver:userDriver delegate:g_delegate];

    // The game decides when to check (once per launch); Sparkle shouldn't schedule its own prompts.
    g_updater.automaticallyChecksForUpdates = NO;

    NSError* error = nil;
    if (![g_updater startUpdater:&error])
    {
        LOGF_IMPL(Utility, "Sparkle", "Failed to start updater: {}", error.localizedDescription.UTF8String);
        g_updater = nil;
    }
}

bool UpdateChecker::start()
{
    if (!g_updater || g_result == Result::InProgress)
        return false;

    g_result = Result::InProgress;

    // Silent probe: no UI, the result is shown by the title screen.
    [g_updater checkForUpdateInformation];

    return true;
}

UpdateChecker::Result UpdateChecker::check()
{
    return g_result;
}

void UpdateChecker::visitWebsite()
{
    if (!g_updater)
        return;

    // Shows release notes and installs on confirmation; Sparkle quits and relaunches the game itself.
    [g_updater checkForUpdates];
}
