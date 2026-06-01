import Cocoa
import IOKit

// MARK: - Config

// Affirmation visible duration (milliseconds). ~33 ms ≈ 2 frames at 60 Hz —
// below conscious recognition threshold for most readers.
let flashMs: Int = 33
// Backward-mask duration (milliseconds). Random characters at the same spot
// scrub the visual afterimage so you can't consciously re-read what flashed.
let maskMs: Int = 120

// Random interval between actual firings (seconds). launchd ticks every 60 s;
// the binary itself picks a random "next allowed" time within this range and
// exits silently on ticks that arrive too soon.
let minIntervalSec: Double = 45.0
let maxIntervalSec: Double = 180.0

// Skip showing if user has been idle (no keyboard/mouse/trackpad input) for
// at least this many seconds. Same safety net as the breathe overlay.
let idleSkipSec: Double = 120.0

// Typography — kept consistent so the visual signature of every flash matches.
let affirmFontSize: CGFloat = 34
let affirmFontWeight: NSFont.Weight = .medium
let affirmTextAlpha: CGFloat = 0.92
// Minimum distance (points) the text bbox must stay from any screen edge.
let edgeMargin: CGFloat = 60

// Paths
let affirmationsURL = URL(fileURLWithPath:
    "/Users/adam/Documents/breathe/affirmations.txt")

let stateDir: URL = {
    let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                        in: .userDomainMask).first!
        .appendingPathComponent("breathe", isDirectory: true)
    try? FileManager.default.createDirectory(at: base,
                                             withIntermediateDirectories: true)
    return base
}()
let nextAllowedURL = stateDir.appendingPathComponent("affirm_next_at")
let indexURL       = stateDir.appendingPathComponent("affirm_index")

// MARK: - Helpers

func systemIdleSeconds() -> Double? {
    var iterator: io_iterator_t = 0
    let r = IOServiceGetMatchingServices(kIOMainPortDefault,
                                         IOServiceMatching("IOHIDSystem"),
                                         &iterator)
    guard r == KERN_SUCCESS else { return nil }
    defer { IOObjectRelease(iterator) }
    let entry = IOIteratorNext(iterator)
    guard entry != 0 else { return nil }
    defer { IOObjectRelease(entry) }
    var props: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(entry, &props,
                                            kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let dict = props?.takeRetainedValue() as? [String: Any],
          let ns = dict["HIDIdleTime"] as? UInt64
    else { return nil }
    return Double(ns) / 1_000_000_000.0
}

func readDouble(_ url: URL) -> Double? {
    guard let s = try? String(contentsOf: url, encoding: .utf8) else { return nil }
    return Double(s.trimmingCharacters(in: .whitespacesAndNewlines))
}
func writeDouble(_ url: URL, _ v: Double) {
    try? String(v).write(to: url, atomically: true, encoding: .utf8)
}
func readInt(_ url: URL) -> Int {
    guard let s = try? String(contentsOf: url, encoding: .utf8),
          let i = Int(s.trimmingCharacters(in: .whitespacesAndNewlines))
    else { return 0 }
    return i
}
func writeInt(_ url: URL, _ v: Int) {
    try? String(v).write(to: url, atomically: true, encoding: .utf8)
}

func loadAffirmations() -> [String] {
    guard let raw = try? String(contentsOf: affirmationsURL, encoding: .utf8) else {
        return []
    }
    return raw.split(whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && !$0.hasPrefix("#") }
}

/// Build a mask string of random letters matching the input length, preserving
/// spaces so the masked block has roughly the same visual shape.
func maskFor(_ text: String) -> String {
    let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
    return String(text.map { ch in
        ch == " " ? " " : chars.randomElement()!
    })
}

func screenForCursor() -> NSScreen {
    let p = NSEvent.mouseLocation
    return NSScreen.screens.first { $0.frame.contains(p) }
        ?? NSScreen.main
        ?? NSScreen.screens[0]
}

func measure(_ text: String, font: NSFont) -> CGSize {
    let s = NSAttributedString(string: text, attributes: [.font: font])
    return s.size()
}

// MARK: - Gate checks

// 1. Idle?
if let idle = systemIdleSeconds(), idle >= idleSkipSec {
    exit(0)
}

// 2. Throttle — randomized cadence.
let now = Date().timeIntervalSince1970
if let nextAt = readDouble(nextAllowedURL), now < nextAt {
    exit(0)
}

// 3. Have affirmations?
let affirmations = loadAffirmations()
guard !affirmations.isEmpty else {
    // No affirmations yet — still schedule the next attempt so we don't
    // hammer the disk every 60s once you've populated the file.
    let gap = Double.random(in: minIntervalSec...maxIntervalSec)
    writeDouble(nextAllowedURL, now + gap)
    exit(0)
}

// MARK: - Choose what + where

let idx = readInt(indexURL)
let safeIdx = ((idx % affirmations.count) + affirmations.count) % affirmations.count
let affirmation = affirmations[safeIdx]
let mask = maskFor(affirmation)

let font = NSFont.systemFont(ofSize: affirmFontSize, weight: affirmFontWeight)
let textSize = measure(affirmation, font: font)
let maskSize = measure(mask, font: font)
// Window must fit the larger of the two so the swap doesn't reflow.
let winW = ceil(max(textSize.width, maskSize.width)) + 8
let winH = ceil(max(textSize.height, maskSize.height)) + 4

let screen = screenForCursor()
let sf = screen.frame
let availW = max(0, sf.width  - winW - edgeMargin * 2)
let availH = max(0, sf.height - winH - edgeMargin * 2)
let originX = sf.minX + edgeMargin + CGFloat.random(in: 0...availW)
let originY = sf.minY + edgeMargin + CGFloat.random(in: 0...availH)
let winRect = NSRect(x: originX, y: originY, width: winW, height: winH)

// Advance index + schedule next gap *before* we display, so even if something
// goes wrong with the display we don't replay the same affirmation forever.
let gap = Double.random(in: minIntervalSec...maxIntervalSec)
writeDouble(nextAllowedURL, now + gap)
writeInt(indexURL, safeIdx + 1)

// MARK: - Display

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let window = NSWindow(contentRect: winRect,
                      styleMask: [.borderless],
                      backing: .buffered,
                      defer: false,
                      screen: screen)
window.isOpaque = false
window.backgroundColor = .clear
window.hasShadow = false
window.ignoresMouseEvents = true
window.level = .screenSaver
window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                             .stationary, .ignoresCycle]
window.isReleasedWhenClosed = false

let label = NSTextField(labelWithString: affirmation)
label.font = font
label.textColor = NSColor.white.withAlphaComponent(affirmTextAlpha)
label.backgroundColor = .clear
label.isBezeled = false
label.isEditable = false
label.drawsBackground = false
label.alignment = .center
label.frame = NSRect(origin: .zero, size: winRect.size)
label.autoresizingMask = [.width, .height]

let container = NSView(frame: NSRect(origin: .zero, size: winRect.size))
container.addSubview(label)
window.contentView = container
window.orderFrontRegardless()

// Swap to mask after the flash window.
DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(flashMs)) {
    label.stringValue = mask
    label.needsDisplay = true

    // Then tear down after the mask window.
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(maskMs)) {
        NSApp.terminate(nil)
    }
}

app.run()
