#include "fullscreen_macos.h"

#import <AppKit/AppKit.h>
#import <QuartzCore/CAMetalLayer.h>
#include <SDL.h>
#include <string>
#include <set>

void os::macos::SetFullscreenMenuBar(bool isEnabled)
{
    // Read by SDL when the window enters fullscreen.
    SDL_SetHint("SDL_VIDEO_MAC_FULLSCREEN_MENU_BAR", isEnabled ? "1" : "0");

    // Apply immediately if already fullscreen.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!(NSApp.presentationOptions & NSApplicationPresentationFullScreen))
            return;

        // SDL forces the menu bar hidden in fullscreen, which overrides auto-hide.
        [NSMenu setMenuBarVisible:isEnabled];

        NSApp.presentationOptions = NSApplicationPresentationFullScreen | (isEnabled
            ? NSApplicationPresentationAutoHideDock | NSApplicationPresentationAutoHideMenuBar
            : NSApplicationPresentationHideDock | NSApplicationPresentationHideMenuBar);
    });
}

double os::macos::GetBackingScale(void* nsWindow)
{
    return ((__bridge NSWindow*)nsWindow).backingScaleFactor;
}

void os::macos::SetOutputScale(void* metalLayer, double scale)
{
    SDL_SetHint("SDL_VIDEO_MAC_METAL_SCALE", std::to_string(scale).c_str());

    auto apply = ^{
        auto layer = (__bridge CAMetalLayer*)metalLayer;
        CGSize size = layer.bounds.size;
        layer.contentsScale = scale;
        layer.drawableSize = CGSizeMake(size.width * scale, size.height * scale);
    };

    // The game runs on the main thread, so queued blocks only run when events are pumped;
    // apply immediately there so the layer is correct before the swapchain is (re)created.
    if ([NSThread isMainThread])
        apply();
    else
        dispatch_async(dispatch_get_main_queue(), apply);
}

std::vector<int> os::macos::GetDisplayModeWidths(void* nsWindow, bool isHiDPI)
{
    auto window = (__bridge NSWindow*)nsWindow;
    auto displayID = CGDirectDisplayID([window.screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue]);

    // Without this option macOS hides the 1x variants of modes that also have a HiDPI variant.
    NSDictionary* options = @{ (__bridge NSString*)kCGDisplayShowDuplicateLowResolutionModes: @YES };
    CFArrayRef modes = CGDisplayCopyAllDisplayModes(displayID, (__bridge CFDictionaryRef)options);

    std::set<int, std::greater<>> unique;

    for (CFIndex i = 0; modes && i < CFArrayGetCount(modes); i++)
    {
        auto mode = (CGDisplayModeRef)CFArrayGetValueAtIndex(modes, i);

        if (!CGDisplayModeIsUsableForDesktopGUI(mode))
            continue;

        int pixelW = int(CGDisplayModeGetPixelWidth(mode));
        int pointW = int(CGDisplayModeGetWidth(mode));

        // HiDPI: the real pixel width of each Retina mode. Otherwise: the "looks like"
        // width from System Settings, rendered at 1x.
        if (pixelW > pointW)
            unique.insert(isHiDPI ? pixelW : pointW);
    }

    if (modes)
        CFRelease(modes);

    return { unique.begin(), unique.end() };
}
