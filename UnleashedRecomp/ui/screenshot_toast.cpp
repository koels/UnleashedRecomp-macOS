#include "screenshot_toast.h"
#include <ui/imgui_utils.h>

constexpr double SLIDE_DURATION = 0.25;
constexpr double HOLD_DURATION = 3.0;

static std::mutex g_mutex;
static std::unique_ptr<GuestTexture> g_thumbnail;
static float g_aspectRatio;
static double g_showTime = -1.0;

// Textures replaced while a frame may still be drawing them are freed one screenshot later.
static std::unique_ptr<GuestTexture> g_previousThumbnail;

void ScreenshotToast::Show(std::unique_ptr<GuestTexture> thumbnail, float aspectRatio)
{
    std::lock_guard lock(g_mutex);

    g_previousThumbnail = std::move(g_thumbnail);
    g_thumbnail = std::move(thumbnail);
    g_aspectRatio = aspectRatio;
    g_showTime = -1.0; // Started by the next Draw(), on ImGui's clock.
}

void ScreenshotToast::Draw()
{
    std::lock_guard lock(g_mutex);

    if (!g_thumbnail)
        return;

    auto time = ImGui::GetTime();
    if (g_showTime < 0.0)
        g_showTime = time;

    auto elapsed = time - g_showTime;
    if (elapsed > SLIDE_DURATION * 2 + HOLD_DURATION)
        return;

    // Slide in from the right, hold, slide back out.
    double slide = std::min({ elapsed, SLIDE_DURATION * 2 + HOLD_DURATION - elapsed, SLIDE_DURATION }) / SLIDE_DURATION;
    slide = 1.0 - pow(1.0 - slide, 3.0);

    auto& res = ImGui::GetIO().DisplaySize;
    auto width = Scale(220);
    auto height = width / g_aspectRatio;
    auto margin = Scale(24);
    auto border = Scale(4);

    ImVec2 min = { float(res.x - (width + margin) * slide), res.y - height - margin };
    ImVec2 max = { min.x + width, min.y + height };

    auto drawList = ImGui::GetBackgroundDrawList();
    drawList->AddRectFilled({ min.x - border + Scale(3), min.y - border + Scale(5) }, { max.x + border + Scale(3), max.y + border + Scale(5) }, IM_COL32(0, 0, 0, 90), Scale(10));
    drawList->AddRectFilled({ min.x - border, min.y - border }, { max.x + border, max.y + border }, IM_COL32(255, 255, 255, 255), Scale(10));
    drawList->AddImageRounded(g_thumbnail.get(), min, max, { 0, 0 }, { 1, 1 }, IM_COL32_WHITE, Scale(7));
}
