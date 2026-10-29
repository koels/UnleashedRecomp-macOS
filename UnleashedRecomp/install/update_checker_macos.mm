#include "update_checker.h"

#import <Sparkle/Sparkle.h>

#include <os/logger.h>

// UpdateChecker backed by Sparkle. The title screen asks check() for the result of a silent
// background probe, and install() downloads and installs it with no Sparkle UI.

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

// Windowless user driver: the title screen asks the player, so every Sparkle prompt is
// answered with "install" and progress is exposed for the in-game message.

static std::atomic<UpdateChecker::InstallState> g_installState = UpdateChecker::InstallState::Idle;
static std::atomic<uint64_t> g_bytesExpected = 0;
static std::atomic<uint64_t> g_bytesReceived = 0;
static std::atomic<float> g_extractProgress = 0.0f;

@interface GameUserDriver : NSObject <SPUUserDriver>
@end

@implementation GameUserDriver

- (void)showUpdatePermissionRequest:(SPUUpdatePermissionRequest *)request reply:(void (^)(SUUpdatePermissionResponse *))reply
{
    reply([[SUUpdatePermissionResponse alloc] initWithAutomaticUpdateChecks:NO sendSystemProfile:NO]);
}

- (void)showUserInitiatedUpdateCheckWithCancellation:(void (^)(void))cancellation {}

- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)appcastItem state:(SPUUserUpdateState *)state reply:(void (^)(SPUUserUpdateChoice))reply
{
    reply(SPUUserUpdateChoiceInstall);
}

- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)downloadData {}
- (void)showUpdateReleaseNotesFailedToDownloadWithError:(NSError *)error {}

- (void)showUpdateNotFoundWithError:(NSError *)error acknowledgement:(void (^)(void))acknowledgement
{
    g_installState = UpdateChecker::InstallState::Failed;
    acknowledgement();
}

- (void)showUpdaterError:(NSError *)error acknowledgement:(void (^)(void))acknowledgement
{
    LOGF_IMPL(Utility, "Sparkle", "Update failed: {}", error.localizedDescription.UTF8String);
    g_installState = UpdateChecker::InstallState::Failed;
    acknowledgement();
}

- (void)showDownloadInitiatedWithCancellation:(void (^)(void))cancellation
{
    g_bytesExpected = 0;
    g_bytesReceived = 0;
    g_installState = UpdateChecker::InstallState::Downloading;
}

- (void)showDownloadDidReceiveExpectedContentLength:(uint64_t)expectedContentLength
{
    g_bytesExpected = expectedContentLength;
}

- (void)showDownloadDidReceiveDataOfLength:(uint64_t)length
{
    g_bytesReceived += length;
}

- (void)showDownloadDidStartExtractingUpdate
{
    g_extractProgress = 0.0f;
    g_installState = UpdateChecker::InstallState::Extracting;
}

- (void)showExtractionReceivedProgress:(double)progress
{
    g_extractProgress = float(progress);
}

- (void)showReadyToInstallAndRelaunch:(void (^)(SPUUserUpdateChoice))reply
{
    g_installState = UpdateChecker::InstallState::Installing;
    reply(SPUUserUpdateChoiceInstall);
}

- (void)showInstallingUpdateWithApplicationTerminated:(BOOL)applicationTerminated retryTerminatingApplication:(void (^)(void))retryTerminatingApplication {}
- (void)showUpdateInstalledAndRelaunched:(BOOL)relaunched acknowledgement:(void (^)(void))acknowledgement { acknowledgement(); }
- (void)showUpdateInFocus {}
- (void)dismissUpdateInstallation {}

@end

static SPUUpdater* g_updater;
static UpdateCheckerDelegate* g_delegate;
static GameUserDriver* g_userDriver;

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

    g_userDriver = [GameUserDriver new];
    g_updater = [[SPUUpdater alloc] initWithHostBundle:NSBundle.mainBundle applicationBundle:NSBundle.mainBundle userDriver:g_userDriver delegate:g_delegate];

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
    install();
}

void UpdateChecker::install()
{
    if (!g_updater)
    {
        g_installState = InstallState::Failed;
        return;
    }

    g_installState = InstallState::Downloading;
    [g_updater checkForUpdates];
}

UpdateChecker::InstallState UpdateChecker::installState()
{
    return g_installState;
}

float UpdateChecker::installProgress()
{
    switch (g_installState)
    {
        case InstallState::Downloading:
            return g_bytesExpected ? std::min(1.0f, float(g_bytesReceived) / float(g_bytesExpected)) : 0.0f;

        case InstallState::Extracting:
            return g_extractProgress;

        default:
            return 1.0f;
    }
}
