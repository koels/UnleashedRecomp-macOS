#pragma once

struct UpdateChecker
{
    enum class Result
    {
        NotStarted,
        InProgress,
        AlreadyUpToDate,
        UpdateAvailable,
        Failed
    };

    static void initialize();
    static bool start();
    static Result check();
    static void visitWebsite();

#ifdef __APPLE__
    enum class InstallState
    {
        Idle,
        Downloading,
        Extracting,
        Installing,
        Failed
    };

    // Downloads and installs the update without any Sparkle windows; the game quits and
    // relaunches when it's ready. Progress is reported for an in-game message.
    static void install();
    static InstallState installState();
    static float installProgress();
#endif
};
