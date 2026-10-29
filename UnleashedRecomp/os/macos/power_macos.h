#pragma once

namespace os::macos
{
    // True while macOS Low Power Mode is on. Cached from the system notification,
    // so this is cheap enough to call every frame.
    bool IsLowPowerMode();
}
