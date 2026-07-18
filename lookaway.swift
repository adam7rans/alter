import Cocoa
import AlterRuntimeSupport

struct LookAwayConfig: Codable {
    var enabled: Bool = true
    var durationSec: Double = 60.0
    var intervalSec: Double = 600.0
    var idleSkipSec: Double = 120.0
    var backgroundOpacity: Double = 1.0
    var textRed: Double = 0.16
    var textGreen: Double = 0.16
    var textBlue: Double = 0.16
    var soundName: String = "Glass"
}

let config: LookAwayConfig = {
    let url = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("breathe/config.json")
    guard let data = try? Data(contentsOf: url),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let inner = root["lookAway"],
          let raw = try? JSONSerialization.data(withJSONObject: inner),
          let parsed = try? JSONDecoder().decode(LookAwayConfig.self, from: raw)
    else { return LookAwayConfig() }
    return parsed
}()

if !config.enabled { exit(0) }
if alterShouldSuppressOverlays() { exit(0) }

let nextAllowedURL = alterStateURL("lookaway_next_at")

func scheduleNextAppearance() {
    alterWriteDouble(nextAllowedURL, Date().timeIntervalSince1970 + config.intervalSec)
}

if let idle = alterSystemIdleSeconds(), idle >= config.idleSkipSec {
    exit(0)
}

let now = Date().timeIntervalSince1970
if let nextAt = alterReadDouble(nextAllowedURL), now < nextAt {
    exit(0)
}

scheduleNextAppearance()

let message = "Focus on something far away."
let overlayColor = NSColor.black.withAlphaComponent(CGFloat(config.backgroundOpacity))
let textColor = NSColor(red: CGFloat(config.textRed),
                        green: CGFloat(config.textGreen),
                        blue: CGFloat(config.textBlue),
                        alpha: 1.0)

final class BlockingWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class OverlayController {
    private var windows: [BlockingWindow] = []
    private var activeSound: NSSound?

    func show() {
        NSApp.activate(ignoringOtherApps: true)

        for screen in NSScreen.screens {
            let window = BlockingWindow(contentRect: screen.frame,
                                        styleMask: [.borderless],
                                        backing: .buffered,
                                        defer: false,
                                        screen: screen)
            window.isOpaque = false
            window.backgroundColor = overlayColor
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.isReleasedWhenClosed = false

            let container = NSView(frame: screen.frame)
            container.wantsLayer = true
            container.layer?.backgroundColor = overlayColor.cgColor

            let label = NSTextField(labelWithString: message)
            label.translatesAutoresizingMaskIntoConstraints = false
            label.backgroundColor = .clear
            label.drawsBackground = false
            label.isBezeled = false
            label.textColor = textColor
            label.alignment = .center
            label.lineBreakMode = .byWordWrapping
            label.maximumNumberOfLines = 2
            label.font = NSFont.systemFont(ofSize: fontSize(for: screen), weight: .medium)

            container.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                label.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor,
                                             multiplier: 0.7),
            ])

            window.contentView = container
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            windows.append(window)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + config.durationSec) { [weak self] in
            self?.finish()
        }
    }

    private func finish() {
        guard config.soundName != "None" else {
            NSApp.terminate(nil)
            return
        }

        let soundName = NSSound.Name(config.soundName)
        guard let sound = NSSound(named: soundName) else {
            NSSound.beep()
            NSApp.terminate(nil)
            return
        }

        activeSound = sound
        sound.play()
        let wait = max(1.5, sound.duration)
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
            NSApp.terminate(nil)
        }
    }

    private func fontSize(for screen: NSScreen) -> CGFloat {
        min(max(screen.frame.width * 0.06, 52), 112)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = OverlayController()
DispatchQueue.main.async { controller.show() }
app.run()
