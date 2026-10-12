// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import Foundation
import IOKit

/// Read the kernel's live switch without spawning pmset on every heartbeat.
/// IOPMrootDomain publishes this Boolean when it applies SleepDisabled.
public enum SystemPowerReadback {
    public static func sleepDisabled() -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let value = IORegistryEntryCreateCFProperty(service, "SleepDisabled" as CFString,
                                                          kCFAllocatorDefault, 0)?.takeRetainedValue(),
              CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return value as? Bool
    }
}
