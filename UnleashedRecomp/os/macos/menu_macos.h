#pragma once

namespace os::macos
{
    // Adds the game's items (updates, mods, Finder shortcuts, bug report) to the app menu SDL creates.
    void AddAppMenuItems();

    // Defined in menu_bridge.cpp, since the game's headers can't be included from Objective-C++.

    // Settings... (Cmd+,): opens Options from the title menu, or pauses gameplay and opens it there.
    void RequestOptionsMenu();

    void RestartGame();
}
