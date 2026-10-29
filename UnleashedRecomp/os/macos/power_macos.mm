#include "power_macos.h"

#include <atomic>

#import <Foundation/Foundation.h>

namespace os::macos
{
    bool IsLowPowerMode()
    {
        static std::atomic<bool> s_isLowPowerMode = false;

        static dispatch_once_t once;
        dispatch_once(&once, ^
        {
            s_isLowPowerMode = NSProcessInfo.processInfo.isLowPowerModeEnabled;

            [NSNotificationCenter.defaultCenter addObserverForName:NSProcessInfoPowerStateDidChangeNotification
                object:nil queue:nil usingBlock:^(NSNotification*)
                {
                    s_isLowPowerMode = NSProcessInfo.processInfo.isLowPowerModeEnabled;
                }];
        });

        return s_isLowPowerMode;
    }
}
