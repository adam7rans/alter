import Cocoa
import AlterRuntimeSupport

struct LookAwayConfig: Codable {
    var enabled: Bool = true
    var durationSec: Double = 60.0
    var countdownSec: Int = 5
    var intervalSec: Double = 600.0
    var idleSkipSec: Double = 120.0
    var backgroundOpacity: Double = 1.0
    var textRed: Double = 0.16
    var textGreen: Double = 0.16
    var textBlue: Double = 0.16
    var soundName: String = "Glass"

    enum CodingKeys: String, CodingKey {
        case enabled, durationSec, countdownSec, intervalSec, idleSkipSec
        case backgroundOpacity, textRed, textGreen, textBlue, soundName
    }

    init() {}

    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
        durationSec = try container.decodeIfPresent(Double.self, forKey: .durationSec) ?? durationSec
        countdownSec = try container.decodeIfPresent(Int.self, forKey: .countdownSec) ?? countdownSec
        intervalSec = try container.decodeIfPresent(Double.self, forKey: .intervalSec) ?? intervalSec
        idleSkipSec = try container.decodeIfPresent(Double.self, forKey: .idleSkipSec) ?? idleSkipSec
        backgroundOpacity = try container.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? backgroundOpacity
        textRed = try container.decodeIfPresent(Double.self, forKey: .textRed) ?? textRed
        textGreen = try container.decodeIfPresent(Double.self, forKey: .textGreen) ?? textGreen
        textBlue = try container.decodeIfPresent(Double.self, forKey: .textBlue) ?? textBlue
        soundName = try container.decodeIfPresent(String.self, forKey: .soundName) ?? soundName
    }
}

let loadedConfig: (lookAway: LookAwayConfig, breatheFontSize: CGFloat) = {
    let url = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("breathe/config.json")
    guard let data = try? Data(contentsOf: url),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let inner = root["lookAway"],
          let raw = try? JSONSerialization.data(withJSONObject: inner),
          let parsed = try? JSONDecoder().decode(LookAwayConfig.self, from: raw)
    else { return (LookAwayConfig(), 220) }
    let breathe = root["breathe"] as? [String: Any]
    let fontSize = (breathe?["fontSize"] as? NSNumber)?.doubleValue ?? 220
    return (parsed, CGFloat(fontSize))
}()
let config = loadedConfig.lookAway
let countdownFontSize = loadedConfig.breatheFontSize

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
    private var windows: [NSWindow] = []
    private var countdownLabels: [NSTextField] = []
    private var activeSound: NSSound?

    func show() {
        guard config.countdownSec > 0 else {
            showBreak()
            return
        }

        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame,
                                  styleMask: [.borderless],
                                  backing: .buffered,
                                  defer: false,
                                  screen: screen)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.isReleasedWhenClosed = false

            let container = NSView(frame: screen.frame)
            let label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.backgroundColor = .clear
            label.drawsBackground = false
            label.isBezeled = false
            label.alignment = .center
            container.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])

            window.contentView = container
            window.orderFrontRegardless()
            windows.append(window)
            countdownLabels.append(label)
        }

        updateCountdown(config.countdownSec)
    }

    private func updateCountdown(_ remaining: Int) {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.8)
        shadow.shadowBlurRadius = 12
        let value = NSAttributedString(
            string: "\(remaining)",
            attributes: [
                .font: NSFont.systemFont(ofSize: countdownFontSize, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.9),
                .shadow: shadow,
            ]
        )
        countdownLabels.forEach { $0.attributedStringValue = value }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            if remaining > 1 {
                self?.updateCountdown(remaining - 1)
            } else {
                self?.showBreak()
            }
        }
    }

    private func showBreak() {
        windows.forEach { $0.close() }
        windows.removeAll()
        countdownLabels.removeAll()
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
