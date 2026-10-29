#include "CTitleStateIntro_patches.h"
#include <api/SWA.h>
#include <install/update_checker.h>
#include <locale/locale.h>
#include <os/logger.h>
#include <ui/fader.h>
#include <ui/message_window.h>
#include <user/achievement_manager.h>
#include <user/paths.h>
#include <app.h>
#include <ui/game_window.h>

static std::atomic<bool> g_faderBegun = false;

bool g_quitMessageOpen = false;
static int g_quitMessageResult = -1;

static std::atomic<bool> g_corruptSaveMessageOpen = false;
static int g_corruptSaveMessageResult = -1;

static std::atomic<bool> g_corruptAchievementsMessageOpen = false;
static int g_corruptAchievementsMessageResult = -1;

static std::atomic<bool> g_updateAvailableMessageOpen = false;
static int g_updateAvailableMessageResult = -1;

static bool ProcessQuitMessage()
{
    if (!g_quitMessageOpen)
        return false;

    std::array<std::string, 2> options = { Localise("Common_Yes"), Localise("Common_No") };

    if (MessageWindow::Open(Localise("Title_Message_Quit"), &g_quitMessageResult, options, 1) == MSG_CLOSED)
    {
        if (!g_quitMessageResult)
        {
            Fader::FadeOut(1, []() { App::Exit(); });
            g_faderBegun = true;
        }

        g_quitMessageOpen = false;
        g_quitMessageResult = -1;
    }

    return true;
}

static bool ProcessCorruptSaveMessage()
{
    if (!g_corruptSaveMessageOpen)
        return false;

    if (MessageWindow::Open(Localise("Title_Message_SaveDataCorrupt"), &g_corruptSaveMessageResult) == MSG_CLOSED)
    {
        g_corruptSaveMessageOpen = false;
        g_corruptSaveMessageOpen.notify_one();
        g_corruptSaveMessageResult = -1;
    }

    return true;
}

static bool ProcessCorruptAchievementsMessage()
{
    if (!g_corruptAchievementsMessageOpen)
        return false;

    auto message = AchievementManager::BinStatus == EAchBinStatus::IOError
        ? Localise("Title_Message_AchievementDataIOError")
        : Localise("Title_Message_AchievementDataCorrupt");

    if (MessageWindow::Open(message, &g_corruptAchievementsMessageResult) == MSG_CLOSED)
    {
        // Create a new save file if the file was successfully loaded and failed validation.
        // If the file couldn't be opened, restarting may fix this error, so it isn't worth clearing the data for.
        if (AchievementManager::BinStatus != EAchBinStatus::IOError)
            AchievementManager::SaveBinary(true);

        g_corruptAchievementsMessageOpen = false;
        g_corruptAchievementsMessageOpen.notify_one();
        g_corruptAchievementsMessageResult = -1;
    }

    return true;
}

#ifdef __APPLE__
static bool g_isInstallingUpdate = false;

// Keeps the title screen on a progress message while Sparkle downloads and installs.
// Sparkle quits and relaunches the game when it's done; on failure the title screen resumes.
static void ProcessUpdateInstall()
{
    auto progress = int(UpdateChecker::installProgress() * 100.0f);

    switch (UpdateChecker::installState())
    {
        case UpdateChecker::InstallState::Downloading:
            MessageWindow::SetText(fmt::format("Downloading update...\n\n{}%", progress));
            break;

        case UpdateChecker::InstallState::Extracting:
            MessageWindow::SetText(fmt::format("Preparing update...\n\n{}%", progress));
            break;

        case UpdateChecker::InstallState::Installing:
            MessageWindow::SetText("Installing update...\n\nThe game will restart automatically.");
            break;

        case UpdateChecker::InstallState::Failed:
            LOGN_ERROR("Update installation failed.");
            MessageWindow::Close();
            g_isInstallingUpdate = false;
            g_updateAvailableMessageOpen = false;
            g_updateAvailableMessageOpen.notify_one();
            break;

        default:
            break;
    }
}
#endif

static bool ProcessUpdateAvailableMessage()
{
    if (!g_updateAvailableMessageOpen)
        return false;

#ifdef __APPLE__
    if (g_isInstallingUpdate)
    {
        ProcessUpdateInstall();
        return true;
    }
#endif

    std::array<std::string, 2> options = { Localise("Common_Yes"), Localise("Common_No") };

    if (MessageWindow::Open(Localise("Title_Message_UpdateAvailable"), &g_updateAvailableMessageResult, options) == MSG_CLOSED)
    {
        if (!g_updateAvailableMessageResult)
        {
#ifdef __APPLE__
            UpdateChecker::install();
            MessageWindow::OpenProgress("Downloading update...");
            g_isInstallingUpdate = true;
            g_updateAvailableMessageResult = -1;

            return true;
#else
            Fader::FadeOut(1,
            //
                []()
                {
                    UpdateChecker::visitWebsite();
                    App::Exit();
                }
            );

            g_faderBegun = true;
#endif
        }

        g_updateAvailableMessageOpen = false;
        g_updateAvailableMessageOpen.notify_one();
        g_updateAvailableMessageResult = -1;
    }

    return true;
}

void StorageDevicePromptMidAsmHook() {}

// Save data validation hook.
PPC_FUNC_IMPL(__imp__sub_822C55B0);
PPC_FUNC(sub_822C55B0)
{
    App::s_isSaveDataCorrupt = true;
    g_corruptSaveMessageOpen = true;
    g_corruptSaveMessageOpen.wait(true);
    ctx.r3.u32 = 0;
}

void PressStartSaveLoadThreadMidAsmHook()
{
    if (UpdateChecker::check() == UpdateChecker::Result::UpdateAvailable)
    {
        g_updateAvailableMessageOpen = true;
        g_updateAvailableMessageOpen.wait(true);
        g_faderBegun.wait(true);
    }

    if (!AchievementManager::LoadBinary())
        LOGFN_ERROR("Failed to load achievement data... (status code {})", (int)AchievementManager::BinStatus);

    if (AchievementManager::BinStatus != EAchBinStatus::Success)
    {
        g_corruptAchievementsMessageOpen = true;
        g_corruptAchievementsMessageOpen.wait(true);
    }
}

// SWA::CTitleStateIntro::Update
PPC_FUNC_IMPL(__imp__sub_82587E50);
PPC_FUNC(sub_82587E50)
{
    GameWindow::s_lastTitleTime = App::s_time;

    auto pTitleStateIntro = (SWA::CTitleStateIntro*)g_memory.Translate(ctx.r3.u32);
    auto pTime = (be<float>*)((uint8_t*)pTitleStateIntro->GetContextBase() + 0x10C);

    if (*SWA::SGlobals::ms_IsAutoSaveWarningShown)
    {
        __imp__sub_82587E50(ctx, base);
    }
    else if (!ProcessUpdateAvailableMessage() && !ProcessCorruptSaveMessage() && !ProcessCorruptAchievementsMessage() && !g_faderBegun)
    {
        if (auto pInputState = SWA::CInputState::GetInstance())
        {
            if (pInputState->GetPadState().IsTapped(SWA::eKeyState_B) && *pTime > 0.5f)
                g_quitMessageOpen = true;
        }

        if (!ProcessQuitMessage())
            __imp__sub_82587E50(ctx, base);
    }
}
