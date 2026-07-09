import SwiftUI
import AppKit
import Foundation

// MARK: - Config models (kept in lockstep with breathe.swift / affirm.swift)

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

struct RootConfig: Codable {
    var breathe: BreatheConfig = BreatheConfig()
    var affirm: AffirmConfig   = AffirmConfig()
}

// MARK: - Config store

@MainActor
final class Store: ObservableObject {
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
    private var savedResetWork: DispatchWorkItem?

    @Published var breathe: BreatheConfig {
        didSet { if oldValue != breathe { save() } }
    }
    @Published var affirm: AffirmConfig {
        didSet { if oldValue != affirm { save() } }
    }

    init() {
        if let data = try? Data(contentsOf: Self.url),
           let root = try? JSONDecoder().decode(RootConfig.self, from: data) {
            self.breathe = root.breathe
            self.affirm  = root.affirm
        } else {
            self.breathe = BreatheConfig()
            self.affirm  = AffirmConfig()
        }
    }

    func save() {
        saveState = .saving
        savedResetWork?.cancel()

        let root = RootConfig(breathe: breathe, affirm: affirm)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(root) else { return }
        try? data.write(to: Self.url, options: .atomic)

        // Briefly show "Saving…" before flipping to "Saved!", then fade to idle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            self.saveState = .saved
            let reset = DispatchWorkItem { [weak self] in self?.saveState = .idle }
            self.savedResetWork = reset
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: reset)
        }
    }

    // MARK: - Actions

    /// Directory containing the alterprefs binary; the breathe/affirm binaries
    /// and affirmations.txt sit alongside it.
    static let binDir: URL = Bundle.main.bundleURL

    func fireBreathe() { run("breathe", clearing: "breathe_next_at") }
    func fireAffirm()  { run("affirm",  clearing: "affirm_next_at") }
    func previewAffirm() { run("affirm", args: ["--preview"], clearing: "affirm_next_at") }

    private func run(_ name: String, args: [String] = [], clearing stateFile: String) {
        let stateURL = Self.url.deletingLastPathComponent()
            .appendingPathComponent(stateFile)
        try? FileManager.default.removeItem(at: stateURL)
        let bin = Self.binDir.appendingPathComponent(name)
        let task = Process()
        task.executableURL = bin
        task.arguments = args
        try? task.run()
    }

    func openAffirmationsFile() {
        let url = Self.binDir.appendingPathComponent("affirmations.txt")
        NSWorkspace.shared.open(url)
    }
}

// MARK: - App entry

@main
struct AlterPrefsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = Store()

    var body: some Scene {
        MenuBarExtra("alter", systemImage: "waveform") {
            PrefsView()
                .environmentObject(store)
                .frame(width: 380)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: - UI

struct PrefsView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BreatheSection()
            Divider()
            AffirmSection()
            Divider()
            FooterBar()
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct BreatheSection: View {
    @EnvironmentObject var store: Store
    @State private var showColorPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle("breathe", isOn: $store.breathe.enabled)
                    .toggleStyle(.switch)
                    .font(.headline)
                Spacer()
                Button("Fire now") { store.fireBreathe() }
                    .controlSize(.small)
            }
            Group {
                ParamSlider("Interval min", $store.breathe.minIntervalSec, 30...600, fmt: "%.0f s")
                ParamSlider("Interval max", $store.breathe.maxIntervalSec, 60...1800, fmt: "%.0f s")
                ParamSlider("Display dur",  $store.breathe.displaySeconds, 2...12, fmt: "%.1f s")
                ParamSlider("Fade in",      $store.breathe.fadeInSeconds, 0.1...4, fmt: "%.1f s")
                ParamSlider("Wave amp",     $store.breathe.waveAmplitudePx, 0...30, fmt: "%.0f px")
                ParamSlider("Wave freq",    $store.breathe.waveFrequency, 0...5, fmt: "%.1f")
                ParamSlider("Wave speed",   $store.breathe.waveSpeed, 0...5, fmt: "%.1f")
                ParamSlider("Font size",    $store.breathe.fontSize, 80...400, fmt: "%.0f pt")
                ParamSlider("Opacity",      $store.breathe.fontAlpha, 0...1, fmt: "%.0f%%", mult: 100)
                HStack(spacing: 8) {
                    Text("Overlay")
                        .frame(width: 92, alignment: .leading)
                        .font(.callout)
                    Button {
                        showColorPicker.toggle()
                    } label: {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(red: store.breathe.overlayRed,
                                        green: store.breathe.overlayGreen,
                                        blue: store.breathe.overlayBlue)
                                    .opacity(store.breathe.overlayAlpha))
                            .frame(height: 22)
                            .overlay(RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.secondary.opacity(0.4)))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showColorPicker, arrowEdge: .bottom) {
                        ColorPickerPopover().environmentObject(store)
                    }
                }
            }
            .disabled(!store.breathe.enabled)
            .opacity(store.breathe.enabled ? 1.0 : 0.4)
        }
        .padding(14)
    }
}

struct ColorPickerPopover: View {
    @EnvironmentObject var store: Store

    private let presets: [(String, Double, Double, Double)] = [
        ("Skyblue", 0.0, 0.45, 0.75),
        ("Black",   0.0, 0.0, 0.0),
        ("Indigo",  0.29, 0.0, 0.51),
        ("Teal",    0.0, 0.5, 0.5),
        ("Rose",    0.86, 0.2, 0.4),
        ("Amber",   0.9, 0.55, 0.1),
        ("Forest",  0.1, 0.4, 0.15),
        ("Slate",   0.3, 0.35, 0.42),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overlay color")
                .font(.headline)

            RoundedRectangle(cornerRadius: 6)
                .fill(Color(red: store.breathe.overlayRed,
                            green: store.breathe.overlayGreen,
                            blue: store.breathe.overlayBlue)
                        .opacity(store.breathe.overlayAlpha))
                .frame(height: 44)
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.4)))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                      spacing: 8) {
                ForEach(presets, id: \.0) { p in
                    Button {
                        store.breathe.overlayRed = p.1
                        store.breathe.overlayGreen = p.2
                        store.breathe.overlayBlue = p.3
                    } label: {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(red: p.1, green: p.2, blue: p.3))
                            .frame(height: 26)
                            .overlay(RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.secondary.opacity(0.4)))
                    }
                    .buttonStyle(.plain)
                    .help(p.0)
                }
            }

            Divider()

            ParamSlider("Red",     $store.breathe.overlayRed, 0...1, fmt: "%.0f", mult: 255)
            ParamSlider("Green",   $store.breathe.overlayGreen, 0...1, fmt: "%.0f", mult: 255)
            ParamSlider("Blue",    $store.breathe.overlayBlue, 0...1, fmt: "%.0f", mult: 255)
            ParamSlider("Opacity", $store.breathe.overlayAlpha, 0...1, fmt: "%.0f%%", mult: 100)
        }
        .padding(16)
        .frame(width: 320)
    }
}

struct AffirmSection: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle("affirm", isOn: $store.affirm.enabled)
                    .toggleStyle(.switch)
                    .font(.headline)
                Spacer()
                HStack(spacing: 8) {
                    Button("Preview") { store.previewAffirm() }
                        .controlSize(.small)
                    Button("Fire now") { store.fireAffirm() }
                        .controlSize(.small)
                }
            }
            Group {
                ParamSlider("Interval min", $store.affirm.minIntervalSec, 5...300, fmt: "%.0f s")
                ParamSlider("Interval max", $store.affirm.maxIntervalSec, 15...600, fmt: "%.0f s")
                ParamSliderInt("Flash ms",  $store.affirm.flashMs, 8...500)
                ParamSliderInt("Mask ms",   $store.affirm.maskMs, 0...500)
                ParamSlider("Font size",    $store.affirm.fontSize, 14...80, fmt: "%.0f pt")
                ParamSlider("Opacity",      $store.affirm.textAlpha, 0...1, fmt: "%.0f%%", mult: 100)
                ParamSlider("Edge margin",  $store.affirm.edgeMargin, 0...200, fmt: "%.0f px")
            }
            .disabled(!store.affirm.enabled)
            .opacity(store.affirm.enabled ? 1.0 : 0.4)
        }
        .padding(14)
    }
}

struct FooterBar: View {
    @EnvironmentObject var store: Store
    var body: some View {
        HStack {
            Button("Edit affirmations…") { store.openAffirmationsFile() }
                .buttonStyle(.link)
            Spacer()
            SaveStatusView()
            Spacer()
            Button("Quit alter") { NSApp.terminate(nil) }
                .buttonStyle(.link)
        }
        .padding(14)
    }
}

struct SaveStatusView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        Group {
            switch store.saveState {
            case .idle:
                EmptyView()
            case .saving:
                HStack(spacing: 5) {
                    ProgressView().controlSize(.small)
                    Text("Saving…")
                }
                .foregroundColor(.secondary)
            case .saved:
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Saved!")
                }
                .foregroundColor(.green)
            }
        }
        .font(.caption)
        .animation(.easeInOut(duration: 0.2), value: store.saveState)
    }
}

struct ParamSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var fmt: String = "%.1f"
    var mult: Double = 1.0

    init(_ label: String, _ value: Binding<Double>,
         _ range: ClosedRange<Double>,
         fmt: String = "%.1f", mult: Double = 1.0) {
        self.label = label
        self._value = value
        self.range = range
        self.fmt = fmt
        self.mult = mult
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 92, alignment: .leading)
                .font(.callout)
            Slider(value: $value, in: range)
            Text(String(format: fmt, value * mult))
                .frame(width: 56, alignment: .trailing)
                .font(.callout.monospacedDigit())
                .foregroundColor(.secondary)
        }
    }
}

struct ParamSliderInt: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    init(_ label: String, _ value: Binding<Int>, _ range: ClosedRange<Int>) {
        self.label = label
        self._value = value
        self.range = range
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 92, alignment: .leading)
                .font(.callout)
            Slider(value: Binding(
                get: { Double(value) },
                set: { value = Int($0.rounded()) }
            ), in: Double(range.lowerBound)...Double(range.upperBound))
            Text("\(value)")
                .frame(width: 56, alignment: .trailing)
                .font(.callout.monospacedDigit())
                .foregroundColor(.secondary)
        }
    }
}
