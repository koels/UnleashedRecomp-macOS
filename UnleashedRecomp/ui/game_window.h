#pragma once

#include <plume_render_interface_types.h>
#include <user/config.h>
#include <sdl_events.h>

#define DEFAULT_WIDTH 1280
#define DEFAULT_HEIGHT 720
#define MIN_WIDTH 640
#define MIN_HEIGHT 480

class GameWindow
{
public:
    static inline SDL_Window* s_pWindow = nullptr;
    static inline plume::RenderWindow s_renderWindow;

    static inline int s_x;
    static inline int s_y;
    static inline int s_width = DEFAULT_WIDTH;
    static inline int s_height = DEFAULT_HEIGHT;

    static inline bool s_isFocused;
    static inline bool s_isIconNight;
    static inline bool s_isFullscreenCursorVisible = true;

    // Last App::s_time at which actual gameplay (stage running, not paused) was observed.
    static inline double s_lastGameplayTime = -1.0;
    static inline bool s_isGameplay = false;

    // Last App::s_time at which the title screen (intro, autosave notice or menu) was updating.
    static inline double s_lastTitleTime = -1.0;
    static inline bool s_isChangingDisplay;

    static SDL_Surface* GetIconSurface(void* pIconBmp, size_t iconSize);
    static void SetIcon(void* pIconBmp, size_t iconSize);
    static void SetIcon(bool isNight = false);
    static const char* GetTitle();
    static void SetTitle(const char* title = nullptr);
    static void SetTitleBarColour();
    static bool IsFullscreen();
    static bool SetFullscreen(bool isEnabled);
    static void SetFullscreenCursorVisibility(bool isVisible);
    static bool IsMaximised();
    static EWindowState SetMaximised(bool isEnabled);
    static SDL_Rect GetDimensions();
    static void GetSizeInPixels(int *w, int *h);
    static void SetDimensions(int w, int h, int x = SDL_WINDOWPOS_CENTERED, int y = SDL_WINDOWPOS_CENTERED);
    static void ResetDimensions();
    static uint32_t GetWindowFlags();
    static int GetDisplayCount();
    static int GetDisplay();
    static void SetDisplay(int displayIndex);
    static std::vector<SDL_DisplayMode> GetDisplayModes(bool ignoreInvalidModes = true, bool ignoreRefreshRates = true);
#ifdef __APPLE__
    // Fullscreen output resolutions: index 0 is native for the HiDPI setting, then the screen's
    // HiDPI or 1x display modes (matching the HiDPI setting), largest first.
    static const std::vector<std::pair<int, int>>& GetFullscreenResolutions();
    static void UpdateOutputScale();
#endif
    static int FindNearestDisplayMode();
    static bool IsPositionValid();
    static void Init(const char* sdlVideoDriver = nullptr);
    static void Update();
};
