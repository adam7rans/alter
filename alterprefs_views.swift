import SwiftUI
import AppKit

struct PrefsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BreatheSection()
            Divider()
            AffirmSection()
            Divider()
            LookAwaySection()
            Divider()
            FooterBar()
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct BreatheSection: View {
    @EnvironmentObject private var store: Store
    @State private var showColorPicker = false
    private let mediaSuppressed = mediaSuppressionActive()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle("breathe", isOn: $store.breathe.enabled)
                    .toggleStyle(.switch)
                    .font(.headline)
                Spacer()
                Button("Fire now") { store.fireBreathe() }
                    .controlSize(.small)
                    .disabled(mediaSuppressed)
            }
            Group {
                ParamSlider("Interval min", $store.breathe.minIntervalSec, 30...600, fmt: "%.0f s")
                ParamSlider("Interval max", $store.breathe.maxIntervalSec, 60...1800, fmt: "%.0f s")
                ParamSlider("Display dur", $store.breathe.displaySeconds, 2...12, fmt: "%.1f s")
                ParamSlider("Fade in", $store.breathe.fadeInSeconds, 0.1...4, fmt: "%.1f s")
                ParamSlider("Wave amp", $store.breathe.waveAmplitudePx, 0...30, fmt: "%.0f px")
                ParamSlider("Wave freq", $store.breathe.waveFrequency, 0...5, fmt: "%.1f")
                ParamSlider("Wave speed", $store.breathe.waveSpeed, 0...5, fmt: "%.1f")
                ParamSlider("Font size", $store.breathe.fontSize, 80...400, fmt: "%.0f pt")
                ParamSlider("Opacity", $store.breathe.fontAlpha, 0...1, fmt: "%.0f%%", mult: 100)
                HStack(spacing: 8) {
                    Text("Overlay")
                        .frame(width: 92, alignment: .leading)
                        .font(.callout)
                    Button { showColorPicker.toggle() } label: {
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
                        BreatheColorPickerPopover()
                    }
                }
            }
            .disabled(!store.breathe.enabled)
            .opacity(store.breathe.enabled ? 1.0 : 0.4)
            if mediaSuppressed {
                Text("Paused while OBS Studio or VLC is open.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
    }
}

struct BreatheColorPickerPopover: View {
    @EnvironmentObject private var store: Store

    private let presets: [(String, Double, Double, Double)] = [
        ("Skyblue", 0.0, 0.45, 0.75),
        ("Black", 0.0, 0.0, 0.0),
        ("Indigo", 0.29, 0.0, 0.51),
        ("Teal", 0.0, 0.5, 0.5),
        ("Rose", 0.86, 0.2, 0.4),
        ("Amber", 0.9, 0.55, 0.1),
        ("Forest", 0.1, 0.4, 0.15),
        ("Slate", 0.3, 0.35, 0.42),
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
                ForEach(presets, id: \.0) { preset in
                    Button {
                        store.breathe.overlayRed = preset.1
                        store.breathe.overlayGreen = preset.2
                        store.breathe.overlayBlue = preset.3
                    } label: {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(red: preset.1, green: preset.2, blue: preset.3))
                            .frame(height: 26)
                            .overlay(RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.secondary.opacity(0.4)))
                    }
                    .buttonStyle(.plain)
                    .help(preset.0)
                }
            }
            Divider()
            ParamSlider("Red", $store.breathe.overlayRed, 0...1, fmt: "%.0f", mult: 255)
            ParamSlider("Green", $store.breathe.overlayGreen, 0...1, fmt: "%.0f", mult: 255)
            ParamSlider("Blue", $store.breathe.overlayBlue, 0...1, fmt: "%.0f", mult: 255)
            ParamSlider("Opacity", $store.breathe.overlayAlpha, 0...1, fmt: "%.0f%%", mult: 100)
        }
        .padding(16)
        .frame(width: 320)
    }
}

struct AffirmSection: View {
    @EnvironmentObject private var store: Store

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
                ParamSliderInt("Flash ms", $store.affirm.flashMs, 8...500)
                ParamSliderInt("Mask ms", $store.affirm.maskMs, 0...500)
                ParamSlider("Font size", $store.affirm.fontSize, 14...80, fmt: "%.0f pt")
                ParamSlider("Opacity", $store.affirm.textAlpha, 0...1, fmt: "%.0f%%", mult: 100)
                ParamSlider("Edge margin", $store.affirm.edgeMargin, 0...200, fmt: "%.0f px")
            }
            .disabled(!store.affirm.enabled)
            .opacity(store.affirm.enabled ? 1.0 : 0.4)
            Text("Preview is the visible test path. Fire now uses your actual flash and opacity settings.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(14)
    }
}

struct LookAwaySection: View {
    @EnvironmentObject private var store: Store
    @State private var showColorPicker = false
    private let mediaSuppressed = mediaSuppressionActive()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle("look away", isOn: $store.lookAway.enabled)
                    .toggleStyle(.switch)
                    .font(.headline)
                Spacer()
                Button("Fire now") { store.fireLookAway() }
                    .controlSize(.small)
                    .disabled(mediaSuppressed)
            }
            Group {
                ParamSlider("Every", $store.lookAway.intervalSec, 300...3600, fmt: "%.0f min", mult: 1.0 / 60.0)
                ParamSlider("Length", $store.lookAway.durationSec, 10...300, fmt: "%.0f s")
                ParamSlider("Bg opacity", $store.lookAway.backgroundOpacity, 0.6...1.0, fmt: "%.0f%%", mult: 100)
                HStack(spacing: 8) {
                    Text("Text color")
                        .frame(width: 92, alignment: .leading)
                        .font(.callout)
                    Button { showColorPicker.toggle() } label: {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(red: store.lookAway.textRed,
                                        green: store.lookAway.textGreen,
                                        blue: store.lookAway.textBlue))
                            .frame(height: 22)
                            .overlay(RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.secondary.opacity(0.4)))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showColorPicker, arrowEdge: .bottom) {
                        LookAwayTextColorPopover()
                    }
                }
                HStack(spacing: 8) {
                    Text("Sound")
                        .frame(width: 92, alignment: .leading)
                        .font(.callout)
                    Picker("Sound", selection: $store.lookAway.soundName) {
                        ForEach(Store.soundOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
            .disabled(!store.lookAway.enabled)
            .opacity(store.lookAway.enabled ? 1.0 : 0.4)
            if mediaSuppressed {
                Text("Paused while OBS Studio or VLC is open.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
    }
}

struct LookAwayTextColorPopover: View {
    @EnvironmentObject private var store: Store

    private let presets: [(String, Double, Double, Double)] = [
        ("Charcoal", 0.16, 0.16, 0.16),
        ("Smoke", 0.22, 0.22, 0.22),
        ("Slate", 0.2, 0.22, 0.25),
        ("Blue Gray", 0.16, 0.18, 0.22),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Text color")
                .font(.headline)
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(red: store.lookAway.textRed,
                            green: store.lookAway.textGreen,
                            blue: store.lookAway.textBlue))
                .frame(height: 44)
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.4)))
            HStack(spacing: 8) {
                ForEach(presets, id: \.0) { preset in
                    Button {
                        store.lookAway.textRed = preset.1
                        store.lookAway.textGreen = preset.2
                        store.lookAway.textBlue = preset.3
                    } label: {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(red: preset.1, green: preset.2, blue: preset.3))
                            .frame(height: 26)
                    }
                    .buttonStyle(.plain)
                    .help(preset.0)
                }
            }
            ParamSlider("Red", $store.lookAway.textRed, 0...1, fmt: "%.0f", mult: 255)
            ParamSlider("Green", $store.lookAway.textGreen, 0...1, fmt: "%.0f", mult: 255)
            ParamSlider("Blue", $store.lookAway.textBlue, 0...1, fmt: "%.0f", mult: 255)
        }
        .padding(16)
        .frame(width: 320)
    }
}

private func mediaSuppressionActive() -> Bool {
    NSWorkspace.shared.runningApplications.contains { app in
        app.bundleIdentifier == "com.obsproject.obs-studio"
            || app.localizedName == "OBS"
            || app.localizedName == "OBS Studio"
            || app.bundleIdentifier == "org.videolan.vlc"
            || app.localizedName == "VLC"
            || app.localizedName == "VLC media player"
    }
}
