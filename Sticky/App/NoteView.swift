import SwiftUI

enum StickyColor {
    static let paper = Color(hex: 0xF3E6C4)
    static let ink = Color(hex: 0x5C4A32)
    static let barFill = Color(hex: 0xC4A15A)
    static let day = Color(hex: 0x6F5B40)
    static let track = Color(hex: 0xDDCFAF)
    static let muted = Color(hex: 0x6F5B40).opacity(0.58)
}

extension Color {
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

struct NoteView: View {
    @StateObject private var model: NoteModel

    @MainActor
    init(model: NoteModel? = nil) {
        _model = StateObject(wrappedValue: model ?? NoteModel())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.rows) { row in
                    VendorBlock(snapshot: row)
                }
            }
            Text(StickyCopy.caption)
                .font(.system(size: 10))
                .foregroundStyle(StickyColor.day.opacity(0.88))
                .padding(.top, 8)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 11)
        .frame(width: 232, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(StickyColor.paper)
        }
        .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 8)
        .padding(.horizontal, 28)
        .padding(.top, 16)
        .padding(.bottom, 32)
        .fixedSize(horizontal: true, vertical: true)
        .overlay {
            GeometryReader { proxy in
                Color.clear.preference(key: NoteSizeKey.self, value: proxy.size)
            }
            .allowsHitTesting(false)
        }
        .onPreferenceChange(NoteSizeKey.self) { size in
            let rounded = CGSize(width: size.width.rounded(), height: size.height.rounded())
            guard rounded.width > 1, rounded.height > 1, rounded != NoteSizeStore.latest else { return }
            NoteSizeStore.latest = rounded
            NotificationCenter.default.post(name: .stickyContentSize, object: NoteSizeBox(rounded))
        }
        .onReceive(NotificationCenter.default.publisher(for: .stickyRefreshRequested)) { _ in
            Task { await model.refresh() }
        }
        .overlay {
            WindowChrome {
                Task { await model.refresh() }
            }
        }
        .task {
            await model.run()
        }
    }
}

private struct VendorBlock: View {
    let snapshot: VendorSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(snapshot.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(StickyColor.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                trailing
            }
            if case .usage(let percent, let fill, let days) = snapshot.kind {
                GluedDaysBar(fill: fill, resetDays: days)
                    .accessibilityLabel("\(snapshot.name) \(percent)% \(UsageMath.dayLabel(resetDays: days))")
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch snapshot.kind {
        case .usage(let percent, _, _):
            Text("\(percent)%")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(StickyColor.ink)
                .monospacedDigit()
                .lineLimit(1)
        case .unavailable(let reason):
            Text(reason)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(StickyColor.muted)
                .lineLimit(1)
        case .loading:
            Text(StickyCopy.loading)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(StickyColor.muted)
                .lineLimit(1)
        }
    }
}

/// Bar length is days until reset (30 days fills the track). Fill is remaining usage.
/// The day label sits on the tail of that bar, so a short bar stays short.
private struct NoteSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 0, next.height > 0 {
            value = next
        }
    }
}

private struct GluedDaysBar: View {
    var fill: Double
    var resetDays: Int

    var body: some View {
        GluedDaysLayout(lengthFraction: UsageMath.barLengthFraction(resetDays: resetDays)) {
            TrackBar(fill: fill)
            Text(UsageMath.dayLabel(resetDays: resetDays))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(StickyColor.day)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
    }
}

private struct TrackBar: View {
    var fill: Double

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 0)
            let clamped = min(1, max(0, fill))
            ZStack(alignment: .leading) {
                Capsule().fill(StickyColor.track)
                Capsule()
                    .fill(StickyColor.barFill)
                    .frame(width: width * clamped)
            }
        }
        .frame(height: 5)
    }
}

private struct GluedDaysLayout: Layout {
    var lengthFraction: Double
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let labelHeight = subviews.dropFirst().first?.sizeThatFits(.unspecified).height ?? 0
        return CGSize(width: proposal.width ?? 0, height: max(labelHeight, 5))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let bar = subviews.first else { return }
        let label = subviews.dropFirst().first
        let labelSize = label?.sizeThatFits(.unspecified) ?? .zero
        let fraction = CGFloat(min(max(lengthFraction, 0), 1))
        let track = max(0, bounds.width - spacing - labelSize.width)
        let barWidth = track * fraction
        let gap: CGFloat = barWidth >= 0.5 ? spacing : 0

        bar.place(
            at: CGPoint(x: bounds.minX, y: bounds.midY),
            anchor: .leading,
            proposal: ProposedViewSize(width: barWidth, height: 5)
        )
        label?.place(
            at: CGPoint(x: bounds.minX + barWidth + gap, y: bounds.midY),
            anchor: .leading,
            proposal: ProposedViewSize(width: labelSize.width, height: labelSize.height)
        )
    }
}

#if DEBUG
private struct PreviewUsageProvider: UsageProvider {
    let vendorName: String
    let percent: Int
    let fill: Double
    let days: Int

    func load(now: Date) async -> VendorSnapshot {
        VendorSnapshot(name: vendorName, kind: .usage(percent: percent, fill: fill, resetDays: days))
    }
}

struct NoteView_Previews: PreviewProvider {
    static var previews: some View {
        // Reference layout only. These numbers are not live usage.
        NoteView(model: NoteModel(providers: [
            PreviewUsageProvider(vendorName: "Cursor", percent: 34, fill: 0.34, days: 3),
            PreviewUsageProvider(vendorName: "Grok", percent: 81, fill: 0.81, days: 26),
            PreviewUsageProvider(vendorName: "Mimo", percent: 11, fill: 0.11, days: 30),
            PreviewUsageProvider(vendorName: "Grok Bot", percent: 55, fill: 0.55, days: 9),
        ]))
        .padding(20)
    }
}
#endif
