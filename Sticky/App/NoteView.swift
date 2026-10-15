import AppKit
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
    @State private var draggingName: String?
    @State private var dragTranslation: CGFloat = 0
    @State private var rowCenters: [String: CGFloat] = [:]
    @State private var dragOrigins: [String: CGFloat] = [:]

    @MainActor
    init(model: NoteModel? = nil) {
        _model = StateObject(wrappedValue: model ?? NoteModel())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.rows) { row in
                    VendorBlock(snapshot: row, longestCycle: longestCycle) { translation, ended in
                        drag(row.name, translation: translation, ended: ended)
                    }
                    .offset(y: draggingName == row.name ? dragTranslation : 0)
                    .zIndex(draggingName == row.name ? 1 : 0)
                    .background {
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: RowCenterKey.self,
                                value: [row.name: geo.frame(in: .named("sticky-rows")).midY]
                            )
                        }
                    }
                }
            }
            .coordinateSpace(name: "sticky-rows")
            .onPreferenceChange(RowCenterKey.self) { rowCenters = $0 }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 12)
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

    private func drag(_ name: String, translation: CGFloat, ended: Bool) {
        if draggingName == nil {
            dragOrigins = rowCenters
        }
        if ended {
            let origin = dragOrigins[name] ?? rowCenters[name] ?? 0
            let y = origin + translation
            let nearest = model.rows.enumerated().min { lhs, rhs in
                let left = abs((dragOrigins[lhs.element.name] ?? 0) - y)
                let right = abs((dragOrigins[rhs.element.name] ?? 0) - y)
                return left < right
            }?.offset
            if let nearest {
                model.reorder(name: name, to: nearest)
            }
            draggingName = nil
            dragTranslation = 0
            dragOrigins = [:]
        } else {
            draggingName = name
            dragTranslation = translation
        }
    }

    private var longestCycle: Double {
        let lengths = model.rows.compactMap { row -> Double? in
            if case .usage(_, _, _, let seconds, _) = row.kind, seconds > 0 { return seconds }
            return nil
        }
        return lengths.max() ?? 1
    }
}

private struct RowCenterKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct VendorBlock: View {
    let snapshot: VendorSnapshot
    var longestCycle: Double
    var onDrag: (CGFloat, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 6) {
                RowGrip { translation, ended in
                    onDrag(translation, ended)
                }
                .frame(width: 14, height: 16, alignment: .leading)
                .accessibilityLabel("拖动 \(snapshot.name)")
                Text(snapshot.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(StickyColor.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                trailing
            }
            if case .usage(let percent, _, let days, let cycleSeconds, let elapsed) = snapshot.kind {
                let fraction = UsageMath.trackWidthFraction(cycleSeconds: cycleSeconds, longestSeconds: longestCycle)
                GeometryReader { geo in
                    let trackWidth = geo.size.width * CGFloat(fraction)
                    CycleTrack(elapsed: elapsed, resetDays: days)
                        .frame(width: max(trackWidth, 0), height: 16, alignment: .leading)
                }
                .frame(height: 16)
                .accessibilityLabel("\(snapshot.name) \(percent)% \(UsageMath.dayLabel(resetDays: days))")
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch snapshot.kind {
        case .usage(let percent, _, _, _, _):
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

/// Track length follows the cycle. Left is remaining time (ochre), right is elapsed time (pale).
/// The day label sits in the longer of those two, flush against the split.
private struct CycleTrack: View {
    var elapsed: Double
    var resetDays: Int

    var body: some View {
        let label = UsageMath.dayLabel(resetDays: resetDays)
        let elapsedFraction = CGFloat(min(1, max(0, elapsed.isFinite ? elapsed : 0)))
        let remainingFraction = 1 - elapsedFraction
        let labelInElapsed = UsageMath.dayLabelInElapsedSegment(elapsed: Double(elapsedFraction))
        GeometryReader { geo in
            let width = max(geo.size.width, 0)
            let split = width * remainingFraction
            let elapsedWidth = width - split
            let textWidth = labelWidth(label)
            let x = labelX(split: split, width: width, textWidth: textWidth, inElapsed: labelInElapsed)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(StickyColor.barFill)
                    .frame(width: width, height: geo.size.height)
                HStack(spacing: 0) {
                    Color.clear.frame(width: split, height: geo.size.height)
                    Rectangle()
                        .fill(StickyColor.track)
                        .frame(width: max(elapsedWidth, 0), height: geo.size.height)
                }
                .frame(width: width, height: geo.size.height, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(StickyColor.ink)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: true)
                    .offset(x: x)
            }
            .frame(width: width, height: geo.size.height, alignment: .leading)
        }
        .frame(height: 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Trailing edge of the label meets the split when it sits in the left segment.
    /// Leading edge meets the split when it sits in the right segment.
    private func labelX(split: CGFloat, width: CGFloat, textWidth: CGFloat, inElapsed: Bool) -> CGFloat {
        if inElapsed {
            let room = max(0, width - textWidth)
            return min(max(0, split), room)
        }
        return max(0, split - textWidth)
    }

    private func labelWidth(_ label: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 10, weight: .medium)
        return (label as NSString).size(withAttributes: [.font: font]).width
    }
}

private struct NoteSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 0, next.height > 0 {
            value = next
        }
    }
}

#if DEBUG
private struct PreviewUsageProvider: UsageProvider {
    let vendorName: String
    let percent: Int
    let fill: Double
    let days: Int

    func load(now: Date) async -> VendorSnapshot {
        VendorSnapshot(
            name: vendorName,
            kind: .usage(
                percent: percent,
                fill: fill,
                resetDays: days,
                cycleSeconds: Double(max(days, 1)) * 86_400,
                elapsed: 0
            )
        )
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
