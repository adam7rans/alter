import Cocoa
import IOKit

// MARK: - Config (read from ~/Library/Application Support/breathe/config.json)

struct AffirmConfig: Codable {
    var enabled: Bool = true
    var flashMs: Int = 33
    var maskMs: Int = 120
    var minIntervalSec: Double = 15.0
    var maxIntervalSec: Double = 60.0
    var idleSkipSec: Double = 120.0
    var fontSize: Double = 34
    var textAlpha: Double = 0.5
    var edgeMargin: Double = 60
}

let _cfg: AffirmConfig = {
    let url = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("breathe/config.json")
    guard let data = try? Data(contentsOf: url),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let inner = root["affirm"],
          let raw = try? JSONSerialization.data(withJSONObject: inner),
          let parsed = try? JSONDecoder().decode(AffirmConfig.self, from: raw)
    else { return AffirmConfig() }
    return parsed
}()

if !_cfg.enabled { exit(0) }

let arguments = Set(CommandLine.arguments.dropFirst())
let isPreviewMode = arguments.contains("--preview")

let flashMs        = isPreviewMode ? max(_cfg.flashMs, 1200) : _cfg.flashMs
let maskMs         = isPreviewMode ? 0 : _cfg.maskMs
let minIntervalSec = _cfg.minIntervalSec
let maxIntervalSec = _cfg.maxIntervalSec
let idleSkipSec    = _cfg.idleSkipSec
let affirmFontSize: CGFloat   = CGFloat(_cfg.fontSize)
let affirmFontWeight: NSFont.Weight = .medium
let affirmTextAlpha: CGFloat  = CGFloat(_cfg.textAlpha)
let edgeMargin: CGFloat       = CGFloat(_cfg.edgeMargin)
let minAffirmFontSize: CGFloat = 1
let windowHPadding: CGFloat = 16
let windowVPadding: CGFloat = 10

// affirmations.txt lives next to the binary so a clone+install works without
// any path tweaking. Bundle.main.bundleURL returns the directory containing
// the running executable for non-bundled CLI binaries.
let affirmationsURL: URL =
    Bundle.main.bundleURL.appendingPathComponent("affirmations.txt")

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

func paragraphStyle() -> NSMutableParagraphStyle {
    let p = NSMutableParagraphStyle()
    p.alignment = .center
    p.lineBreakMode = .byCharWrapping
    return p
}

func measureWrapped(_ text: String, font: NSFont, maxWidth: CGFloat) -> CGSize {
    let s = NSAttributedString(string: text, attributes: [
        .font: font,
        .paragraphStyle: paragraphStyle(),
    ])
    let rect = s.boundingRect(with: NSSize(width: maxWidth,
                                           height: .greatestFiniteMagnitude),
                              options: [.usesLineFragmentOrigin, .usesFontLeading])
    return NSSize(width: ceil(rect.width), height: ceil(rect.height))
}

func effectiveMargin(_ requested: CGFloat, within length: CGFloat) -> CGFloat {
    min(requested, max(0, (length - 1) / 2))
}

struct LayoutResult {
    let font: NSFont
    let contentSize: CGSize
}

func fitLayout(texts: [String], baseFontSize: CGFloat,
               maxContentWidth: CGFloat, maxContentHeight: CGFloat) -> LayoutResult {
    let minFontSize = min(baseFontSize, minAffirmFontSize)
    var candidateSize = baseFontSize
    var lastResult: LayoutResult?

    while candidateSize >= minFontSize {
        let font = NSFont.systemFont(ofSize: candidateSize, weight: affirmFontWeight)
        let sizes = texts.map { measureWrapped($0, font: font, maxWidth: maxContentWidth) }
        let contentSize = CGSize(width: sizes.map(\.width).max() ?? 0,
                                 height: sizes.map(\.height).max() ?? 0)
        let result = LayoutResult(font: font, contentSize: contentSize)
        lastResult = result
        if contentSize.height <= maxContentHeight {
            return result
        }
        candidateSize -= 1
    }

    return lastResult ?? LayoutResult(
        font: NSFont.systemFont(ofSize: minFontSize, weight: affirmFontWeight),
        contentSize: .zero
    )
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

let screen = screenForCursor()
let visibleFrame = screen.visibleFrame
let marginX = effectiveMargin(edgeMargin, within: visibleFrame.width)
let marginY = effectiveMargin(edgeMargin, within: visibleFrame.height)
let usableFrame = visibleFrame.insetBy(dx: marginX, dy: marginY)
let maxContentWidth = max(1, usableFrame.width - windowHPadding * 2)
let maxContentHeight = max(1, usableFrame.height - windowVPadding * 2)
let layout = fitLayout(texts: [affirmation, mask],
                       baseFontSize: affirmFontSize,
                       maxContentWidth: maxContentWidth,
                       maxContentHeight: maxContentHeight)
let font = layout.font
let winW = min(usableFrame.width,
               ceil(layout.contentSize.width) + windowHPadding * 2)
let winH = min(usableFrame.height,
               ceil(layout.contentSize.height) + windowVPadding * 2)
let availW = max(0, usableFrame.width - winW)
let availH = max(0, usableFrame.height - winH)
let originX = usableFrame.minX + CGFloat.random(in: 0...availW)
let originY = usableFrame.minY + CGFloat.random(in: 0...availH)
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

func styled(_ s: String) -> NSAttributedString {
    NSAttributedString(string: s, attributes: [
        .font: font,
        .foregroundColor: NSColor.white.withAlphaComponent(affirmTextAlpha),
        .paragraphStyle: paragraphStyle(),
    ])
}

let label = NSTextField()
label.isBezeled = false
label.isEditable = false
label.drawsBackground = false
label.backgroundColor = .clear
label.alignment = .center
label.lineBreakMode = .byCharWrapping
label.usesSingleLineMode = false
label.maximumNumberOfLines = 0
label.cell?.wraps = true
label.cell?.isScrollable = false
label.attributedStringValue = styled(affirmation)
label.frame = NSRect(x: windowHPadding,
                     y: windowVPadding,
                     width: winRect.width - windowHPadding * 2,
                     height: winRect.height - windowVPadding * 2)
label.autoresizingMask = [.width, .height]

let container = NSView(frame: NSRect(origin: .zero, size: winRect.size))
container.addSubview(label)
window.contentView = container
window.orderFrontRegardless()

// Swap to mask after the flash window.
DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(flashMs)) {
    label.attributedStringValue = styled(mask)
    label.needsDisplay = true

    // Then tear down after the mask window.
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(maskMs)) {
        NSApp.terminate(nil)
    }
}

app.run()
