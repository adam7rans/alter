import AppKit
import Foundation
import IOKit

public func alterStateDirectory() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                        in: .userDomainMask).first!
        .appendingPathComponent("breathe", isDirectory: true)
    try? FileManager.default.createDirectory(at: base,
                                             withIntermediateDirectories: true)
    return base
}

public func alterStateURL(_ name: String) -> URL {
    alterStateDirectory().appendingPathComponent(name)
}

public func alterReadDouble(_ url: URL) -> Double? {
    guard let value = try? String(contentsOf: url, encoding: .utf8) else { return nil }
    return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
}

public func alterWriteDouble(_ url: URL, _ value: Double) {
    try? String(value).write(to: url, atomically: true, encoding: .utf8)
}

public func alterSystemIdleSeconds() -> Double? {
    var iterator: io_iterator_t = 0
    let result = IOServiceGetMatchingServices(kIOMainPortDefault,
                                              IOServiceMatching("IOHIDSystem"),
                                              &iterator)
    guard result == KERN_SUCCESS else { return nil }
    defer { IOObjectRelease(iterator) }

    let entry = IOIteratorNext(iterator)
    guard entry != 0 else { return nil }
    defer { IOObjectRelease(entry) }

    var props: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(entry, &props,
                                            kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let dict = props?.takeRetainedValue() as? [String: Any],
          let idleNs = dict["HIDIdleTime"] as? UInt64
    else { return nil }

    return Double(idleNs) / 1_000_000_000.0
}

public func alterIsOBSRunning() -> Bool {
    NSWorkspace.shared.runningApplications.contains { app in
        app.bundleIdentifier == "com.obsproject.obs-studio"
            || app.localizedName == "OBS"
            || app.localizedName == "OBS Studio"
    }
}
