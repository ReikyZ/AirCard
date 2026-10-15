import Foundation

public enum StickyCopy {
    public static let notConnected = "未接入"
    public static let loading = "读取中"
    public static let signedOut = "未登录"
    public static let unreadable = "无法读取"
    public static let fetchFailed = "获取失败"
    public static let noAllowance = "无额度"
    public static let refresh = "刷新"
    public static let quit = "退出"
}

public enum StickyRoster {
    public static let cursor = "Cursor"
    public static let mimo = "Mimo"
    public static let grokBot = "Grok Bot"

    public static var names: [String] {
        [cursor, mimo, grokBot]
    }
}

public enum VendorOrder {
    public static func arrange(_ rows: [VendorSnapshot], order: [String]) -> [VendorSnapshot] {
        let byName = Dictionary(uniqueKeysWithValues: rows.map { ($0.name, $0) })
        var seen = Set<String>()
        var result: [VendorSnapshot] = []
        for name in order {
            guard let row = byName[name], seen.insert(name).inserted else { continue }
            result.append(row)
        }
        for row in rows where seen.insert(row.name).inserted {
            result.append(row)
        }
        return result
    }

    /// `index` is the slot the row should occupy after the move.
    public static func move(_ name: String, in names: [String], to index: Int) -> [String] {
        guard let from = names.firstIndex(of: name) else { return names }
        var result = names
        result.remove(at: from)
        let destination = min(max(index, 0), result.count)
        result.insert(name, at: destination)
        return result
    }
}

public struct VendorSnapshot: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public var name: String
    public var kind: Kind

    public init(name: String, kind: Kind) {
        self.name = name
        self.kind = kind
    }

    public enum Kind: Equatable, Sendable {
        case loading
        /// Name stays visible. The reason replaces the percent, and there is no bar.
        case unavailable(reason: String)
        /// `percent` is the rounded remaining usage percent, 0...100. It is the number beside the name.
        /// `fill` is that remaining usage percent as a 0...1 fraction. It does not size the bar.
        /// `elapsed` is time already past, `(now - start) / (end - start)`, clamped to 0...1.
        /// The track's left segment is the remaining time. The right segment is this elapsed time.
        /// `cycleSeconds` is the full cycle length, `end - start`.
        /// `resetDays` is whole local calendar days until the cycle end, clamped at 0.
        case usage(percent: Int, fill: Double, resetDays: Int, cycleSeconds: Double, elapsed: Double)
    }

    public static func unavailable(name: String, reason: String) -> VendorSnapshot {
        VendorSnapshot(name: name, kind: .unavailable(reason: reason))
    }
}

public protocol UsageProvider: Sendable {
    var vendorName: String { get }
    var placeholder: VendorSnapshot { get }
    func load(now: Date) async -> VendorSnapshot
}

public extension UsageProvider {
    var placeholder: VendorSnapshot {
        VendorSnapshot(name: vendorName, kind: .loading)
    }
}

public struct UnavailableProvider: UsageProvider {
    public var vendorName: String
    public var reason: String

    public init(vendorName: String, reason: String) {
        self.vendorName = vendorName
        self.reason = reason
    }

    public var placeholder: VendorSnapshot {
        VendorSnapshot.unavailable(name: vendorName, reason: reason)
    }

    public func load(now: Date) async -> VendorSnapshot {
        placeholder
    }
}
