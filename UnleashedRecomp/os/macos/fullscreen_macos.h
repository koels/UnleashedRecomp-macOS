#pragma once

#include <vector>

namespace os::macos
{
    // Lets the menu bar and Dock slide in when the cursor reaches the screen edge in fullscreen.
    void SetFullscreenMenuBar(bool isEnabled);

    // Native pixels per point of the screen the window is on.
    double GetBackingScale(void* nsWindow);

    // Makes the Metal layer (and SDL's view on later resizes) use the given pixels per point,
    // so the swapchain size and the layer always agree. The compositor scales the result to the screen.
    void SetOutputScale(void* metalLayer, double scale);

    // Widths of the screen's desktop-usable Retina modes, largest first: their pixel widths
    // for HiDPI, or their "looks like" widths from System Settings otherwise.
    std::vector<int> GetDisplayModeWidths(void* nsWindow, bool isHiDPI);
}
