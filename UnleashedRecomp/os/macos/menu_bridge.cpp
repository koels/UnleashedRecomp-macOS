#include "menu_macos.h"
#include <ui/game_window.h>
#include <ui/options_menu.h>
#include <app.h>

void os::macos::RequestOptionsMenu()
{
    OptionsMenu::s_openRequestTime = App::s_time;

    // During gameplay, pause first; the pause menu then opens Options.
    if (GameWindow::s_isGameplay)
        GameWindow::s_pauseRequestTime = App::s_time;
}

void os::macos::RestartGame()
{
    App::Restart();
}
