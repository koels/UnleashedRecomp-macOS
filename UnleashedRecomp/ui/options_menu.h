#pragma once

#include <api/SWA.h>

class OptionsMenu
{
public:
    static inline bool s_isVisible = false;
    static inline bool s_isPause = false;
    static inline bool s_isRestartRequired = false;

    static inline SWA::EMenuType s_pauseMenuType;

    // Set by Settings... (Cmd+,) in the menu bar; the title menu or pause menu opens Options
    // if one of them is up within two seconds.
    static inline double s_openRequestTime = -1.0;

    static bool ConsumeOpenRequest();

    static void Init();
    static void Draw();
    static void Open(bool isPause = false, SWA::EMenuType pauseMenuType = SWA::eMenuType_WorldMap);
    static void Close();

    static bool CanClose();
};
