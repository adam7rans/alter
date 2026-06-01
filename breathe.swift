import Cocoa
import IOKit
import CoreImage
import Metal
import MetalKit

// Total time from appearance until fade-out begins (seconds).
// Includes the fade-in, so effective "fully visible" time is
// roughly displaySeconds - fadeInSeconds.
let displaySeconds: Double = 6.0
// Fade-in duration (seconds) — how slowly the word appears.
let fadeInSeconds: Double = 2.0
// Fade-out duration (seconds) — how slowly it disappears.
let fadeSeconds: Double = 1.0

// Sine-wave distortion params (mirrors CAST's CaptionShaderRenderer math).
// frequency = # of wave cycles across the source image along the wave dir.
// speed     = radians per second the wave travels.
// amplitude = max displacement in *pixels* perpendicular to the wave dir.
// angleDeg  = 0 means the wave runs horizontally (text wiggles vertically).
let waveFrequency: CGFloat = 1.2
let waveSpeed: CGFloat = 1.8
let waveAmplitudePx: CGFloat = 9.0
let waveAngleDeg: CGFloat = 0.0

// Skip showing the overlay if the user has been idle (no keyboard, mouse,
// or trackpad activity) for at least this many seconds. Prevents "breathe"
// from firing when you've walked away or the screen is asleep.
let idleSkipSeconds: Double = 120.0

// Desired minimum gap between two overlay appearances, in seconds. launchd
// fires us every 60s; this throttle keeps the actual cadence at ~5 minutes
// while you're active. Drop launchd's StartInterval if you want a snappier
// "first breath" after returning to the machine.
let minIntervalSeconds: Double = 300.0

// File used to remember when we last showed the overlay across runs.
let stateURL: URL = {
    let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                        in: .userDomainMask).first!
        .appendingPathComponent("breathe", isDirectory: true)
    try? FileManager.default.createDirectory(at: base,
                                             withIntermediateDirectories: true)
    return base.appendingPathComponent("last_shown")
}()

func lastShownAt() -> Date? {
    guard let s = try? String(contentsOf: stateURL, encoding: .utf8),
          let t = TimeInterval(s.trimmingCharacters(in: .whitespacesAndNewlines))
    else { return nil }
    return Date(timeIntervalSince1970: t)
}

func recordShownNow() {
    let s = String(Date().timeIntervalSince1970)
    try? s.write(to: stateURL, atomically: true, encoding: .utf8)
}

/// Returns seconds since the last HID (keyboard/mouse) event, or nil on error.
func systemIdleSeconds() -> Double? {
    var iterator: io_iterator_t = 0
    let result = IOServiceGetMatchingServices(
        kIOMainPortDefault,
        IOServiceMatching("IOHIDSystem"),
        &iterator
    )
    guard result == KERN_SUCCESS else { return nil }
    defer { IOObjectRelease(iterator) }

    let entry: io_registry_entry_t = IOIteratorNext(iterator)
    guard entry != 0 else { return nil }
    defer { IOObjectRelease(entry) }

    var props: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let dict = props?.takeRetainedValue() as? [String: Any],
          let idleNs = dict["HIDIdleTime"] as? UInt64
    else { return nil }

    return Double(idleNs) / 1_000_000_000.0
}

// Bail out early if the user is idle. No window, no power assertion — just exit.
if let idle = systemIdleSeconds(), idle >= idleSkipSeconds {
    exit(0)
}

// Throttle: don't show again until at least minIntervalSeconds have passed
// since the last *actual* appearance. (launchd fires us every 60s.)
if let last = lastShownAt(),
   Date().timeIntervalSince(last) < minIntervalSeconds {
    exit(0)
}

recordShownNow()

final class OverlayController {
    var windows: [NSWindow] = []

    func show() {
        for screen in NSScreen.screens {
            let win = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            win.isOpaque = false
            win.backgroundColor = NSColor.black.withAlphaComponent(0.0) // fully transparent bg
            win.hasShadow = false
            win.ignoresMouseEvents = true            // click-through
            win.level = .screenSaver                 // above normal apps & fullscreen
            win.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .stationary,
                .ignoresCycle
            ]
            win.isReleasedWhenClosed = false

            let font = NSFont.systemFont(ofSize: 220, weight: .medium)
            let color = NSColor.white.withAlphaComponent(0.85)
            let textView: NSView = WaveTextView(text: "breathe",
                                                font: font,
                                                color: color,
                                                screen: screen)
                ?? FallbackTextView(text: "breathe", font: font, color: color)
            textView.translatesAutoresizingMaskIntoConstraints = false

            // subtle dark vignette so the word is readable on light backgrounds
            let dim = NSView(frame: screen.frame)
            dim.wantsLayer = true
            dim.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor

            let container = NSView(frame: screen.frame)
            container.addSubview(dim)
            container.addSubview(textView)
            NSLayoutConstraint.activate([
                textView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                textView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                textView.widthAnchor.constraint(equalToConstant: textView.bounds.width),
                textView.heightAnchor.constraint(equalToConstant: textView.bounds.height),
            ])
            dim.autoresizingMask = [.width, .height]

            win.contentView = container
            win.alphaValue = 0.0
            win.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = fadeInSeconds
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                win.animator().alphaValue = 1.0
            }

            windows.append(win)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + displaySeconds) { [weak self] in
            self?.fadeOutAndQuit()
        }
    }

    func fadeOutAndQuit() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = fadeSeconds
            for w in windows { w.animator().alphaValue = 0.0 }
        }, completionHandler: {
            NSApp.terminate(nil)
        })
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // no Dock icon, no menu bar

let controller = OverlayController()
DispatchQueue.main.async { controller.show() }

app.run()

// MARK: - Wave-distorted text rendering
//
// Port of the WebGL sine-displacement shader in CAST's CaptionShaderRenderer
// (see CAST/src/lib/CaptionShaderRenderer.ts). We rasterize the word once into
// a CGImage, wrap it as a CIImage, then apply a CIWarpKernel each frame on a
// Metal-backed view. CIWarpKernel uses the Core Image Kernel Language; the
// kernel math is a near-line-for-line port of the GLSL fragment shader.

final class WaveTextView: MTKView {
    private let sourceImage: CIImage
    private let kernel: CIWarpKernel
    private let ciContext: CIContext
    private let commandQueue: MTLCommandQueue
    private let startTime = CACurrentMediaTime()
    private let amp: CGFloat = waveAmplitudePx

    init?(text: String, font: NSFont, color: NSColor, screen: NSScreen) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let krn = CIWarpKernel(source: WaveTextView.kernelSource)
        else { return nil }

        let scale = screen.backingScaleFactor
        // Pad so that maximum perpendicular displacement never clips the glyphs.
        let padding = max(waveAmplitudePx * 4, 40)
        guard let raster = WaveTextView.rasterize(text: text,
                                                  font: font,
                                                  color: color,
                                                  padding: padding,
                                                  scale: scale)
        else { return nil }

        self.sourceImage = CIImage(cgImage: raster.image)
        self.kernel = krn
        self.commandQueue = queue
        self.ciContext = CIContext(mtlDevice: device,
                                   options: [.workingColorSpace: NSNull()])

        super.init(frame: CGRect(origin: .zero, size: raster.pointSize),
                   device: device)
        framebufferOnly = false
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        wantsLayer = true
        layer?.isOpaque = false
        (layer as? CAMetalLayer)?.isOpaque = false
        autoResizeDrawable = false
        drawableSize = CGSize(width: CGFloat(raster.image.width),
                              height: CGFloat(raster.image.height))
        preferredFramesPerSecond = 60
        isPaused = false
        enableSetNeedsDisplay = false
    }

    required init(coder: NSCoder) { fatalError("not implemented") }

    // Stay invisible to the input system; the parent window already ignores
    // mouse events, but belt-and-suspenders so we never steal focus.
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ rect: CGRect) {
        autoreleasepool {
            guard let drawable = currentDrawable,
                  let cmd = commandQueue.makeCommandBuffer() else { return }

            let t = CGFloat(CACurrentMediaTime() - startTime)
            let a = waveAngleDeg * .pi / 180
            let dir = CIVector(x: cos(a), y: sin(a))
            let extent = sourceImage.extent

            let args: [Any] = [
                t, waveSpeed, waveFrequency, waveAmplitudePx,
                dir, extent.width, extent.height
            ]
            let amp = self.amp
            let roi: CIKernelROICallback = { _, dest in
                dest.insetBy(dx: -amp * 2, dy: -amp * 2)
            }

            guard let warped = kernel.apply(extent: extent,
                                            roiCallback: roi,
                                            image: sourceImage,
                                            arguments: args) else {
                cmd.commit()
                return
            }

            ciContext.render(warped,
                             to: drawable.texture,
                             commandBuffer: cmd,
                             bounds: extent,
                             colorSpace: CGColorSpaceCreateDeviceRGB())
            cmd.present(drawable)
            cmd.commit()
        }
    }

    private static let kernelSource = """
    kernel vec2 wave(float time, float speed, float freq, float amp,
                     vec2 dir, float w, float h) {
        vec2 dc = destCoord();
        vec2 uv = vec2(dc.x / w, dc.y / h);
        float phase = dot(uv, dir) * freq * 6.2831853 + time * speed;
        vec2 perp = vec2(-dir.y, dir.x);
        vec2 disp = perp * sin(phase) * amp;
        return vec2(dc.x + disp.x, dc.y + disp.y);
    }
    """

    private static func rasterize(text: String,
                                  font: NSFont,
                                  color: NSColor,
                                  padding: CGFloat,
                                  scale: CGFloat) -> (image: CGImage, pointSize: CGSize)? {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let s = NSAttributedString(string: text, attributes: attrs)
        let textSize = s.size()
        let wPts = ceil(textSize.width + padding * 2)
        let hPts = ceil(textSize.height + padding * 2)
        let pxW = Int(wPts * scale)
        let pxH = Int(hPts * scale)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: pxW, height: pxH,
            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        let drawRect = CGRect(x: padding, y: padding,
                              width: textSize.width, height: textSize.height)
        s.draw(in: drawRect)
        NSGraphicsContext.restoreGraphicsState()
        guard let img = ctx.makeImage() else { return nil }
        return (img, CGSize(width: wPts, height: hPts))
    }
}

/// Plain-text fallback used only if Metal/Core Image initialization fails
/// (effectively never on modern Macs, but keeps the overlay functional).
final class FallbackTextView: NSView {
    init(text: String, font: NSFont, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color
        ]
        let size = NSAttributedString(string: text, attributes: attrs).size()
        super.init(frame: CGRect(origin: .zero, size: size))
        wantsLayer = true
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.drawsBackground = false
        label.frame = bounds
        label.alignment = .center
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
