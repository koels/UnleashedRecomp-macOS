#pragma once

#include <gpu/video.h>

// macOS-style floating thumbnail after a screenshot is saved.
struct ScreenshotToast
{
    // Thread-safe; called from the thread that saves the screenshot.
    static void Show(std::unique_ptr<GuestTexture> thumbnail, float aspectRatio);
    static void Draw();
};
