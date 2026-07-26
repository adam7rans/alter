import SwiftUI
import AppKit
import Foundation

struct BreatheConfig: Codable, Equatable {
    var enabled: Bool = true
    var displaySeconds: Double = 6.0
    var fadeInSeconds: Double = 2.0
    var fadeSeconds: Double = 1.0
    var waveFrequency: Double = 1.2
    var waveSpeed: Double = 1.8
    var waveAmplitudePx: Double = 9.0
    var waveAngleDeg: Double = 0.0
    var idleSkipSeconds: Double = 120.0
    var minIntervalSec: Double = 180.0
    var maxIntervalSec: Double = 600.0
    var fontSize: Double = 220.0
    var fontAlpha: Double = 0.85
    var overlayRed: Double = 0.0
    var overlayGreen: Double = 0.45
    var overlayBlue: Double = 0.75
    var overlayAlpha: Double = 0.25
}

struct AffirmConfig: Codable, Equatable {
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

struct LookAwayConfig: Codable, Equatable {
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

struct RootConfig: Codable {
    var breathe: BreatheConfig = BreatheConfig()
    var affirm: AffirmConfig = AffirmConfig()
    var lookAway: LookAwayConfig = LookAwayConfig()

    enum CodingKeys: String, CodingKey {
        case breathe
        case affirm
        case lookAway
    }

    init() {}

    init(breathe: BreatheConfig, affirm: AffirmConfig, lookAway: LookAwayConfig) {
        self.breathe = breathe
        self.affirm = affirm
        self.lookAway = lookAway
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        breathe = try container.decodeIfPresent(BreatheConfig.self, forKey: .breathe) ?? BreatheConfig()
        affirm = try container.decodeIfPresent(AffirmConfig.self, forKey: .affirm) ?? AffirmConfig()
        lookAway = try container.decodeIfPresent(LookAwayConfig.self, forKey: .lookAway) ?? LookAwayConfig()
    }
}

@MainActor
final class Store: ObservableObject {
    static let soundOptions = ["None", "Glass", "Hero", "Ping", "Pop", "Purr", "Submarine", "Tink"]

    static let url: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("breathe", isDirectory: true)
        try? FileManager.default.createDirectory(at: base,
                                                 withIntermediateDirectories: true)
        return base.appendingPathComponent("config.json")
    }()

    enum SaveState: Equatable { case idle, saving, saved }

    @Published var saveState: SaveState = .idle
    @Published var breathe: BreatheConfig { didSet { if oldValue != breathe { save() } } }
    @Published var affirm: AffirmConfig { didSet { if oldValue != affirm { save() } } }
    @Published var lookAway: LookAwayConfig { didSet { if oldValue != lookAway { save() } } }

    private var savedResetWork: DispatchWorkItem?

    init() {
        if let data = try? Data(contentsOf: Self.url),
           let root = try? JSONDecoder().decode(RootConfig.self, from: data) {
            breathe = root.breathe
            affirm = root.affirm
            lookAway = root.lookAway
        } else {
            breathe = BreatheConfig()
            affirm = AffirmConfig()
            lookAway = LookAwayConfig()
        }
    }

    func save() {
        saveState = .saving
        savedResetWork?.cancel()

        let root = RootConfig(breathe: breathe, affirm: affirm, lookAway: lookAway)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(root) else { return }
        try? data.write(to: Self.url, options: .atomic)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            saveState = .saved
            let reset = DispatchWorkItem { [weak self] in self?.saveState = .idle }
            savedResetWork = reset
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: reset)
        }
    }

    static let binDir: URL = Bundle.main.bundleURL

    func fireBreathe() { run("breathe", clearing: "breathe_next_at") }
    func fireAffirm() { run("affirm", clearing: "affirm_next_at") }
    func previewAffirm() { run("affirm", args: ["--preview"], clearing: "affirm_next_at") }
    func fireLookAway() { run("lookaway", clearing: "lookaway_next_at") }

    func openAffirmationsFile() {
        NSWorkspace.shared.open(Self.binDir.appendingPathComponent("affirmations.txt"))
    }

    private func run(_ name: String, args: [String] = [], clearing stateFile: String) {
        let stateURL = Self.url.deletingLastPathComponent().appendingPathComponent(stateFile)
        try? FileManager.default.removeItem(at: stateURL)

        let task = Process()
        task.executableURL = Self.binDir.appendingPathComponent(name)
        task.arguments = args
        try? task.run()
    }
}

@main
struct AlterPrefsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = Store()

    var body: some Scene {
        MenuBarExtra("alter", systemImage: "waveform") {
            PrefsView()
                .environmentObject(store)
                .frame(width: 400)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
