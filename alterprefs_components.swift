import SwiftUI
import AppKit

struct FooterBar: View {
    @EnvironmentObject private var store: Store

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
    @EnvironmentObject private var store: Store

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

    init(_ label: String, _ value: Binding<Double>, _ range: ClosedRange<Double>,
         fmt: String = "%.1f", mult: Double = 1.0) {
        self.label = label
        _value = value
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
        _value = value
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
