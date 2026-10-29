#pragma once

namespace os::discord
{
    // Starts a background thread that shows "Playing" Rich Presence over Discord's local IPC socket.
    void Init();
}
