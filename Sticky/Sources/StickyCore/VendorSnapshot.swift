import Foundation

public enum StickyCopy {
    public static let caption = "条长是剩余天数，填充是剩余用量"
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
    public static let pending: [(name: String, reason: String)] = [
        ("Grok", StickyCopy.notConnected),
        ("Mimo", StickyCopy.notConnected),
        ("Grok Bot", StickyCopy.notConnected),
    ]

    public static var names: [String] {
        [cursor] + pending.map(\.name)
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
        /// `percent` is the rounded remaining percent, 0...100.
        /// `fill` is remaining/limit clamped to 0...1.
        /// `resetDays` is clamped at 0.
        case usage(percent: Int, fill: Double, resetDays: Int)
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
