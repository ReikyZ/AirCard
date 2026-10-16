import Foundation

public enum MiniMaxWindow: Sendable {
    /// Coding model's current interval. MiniMax calls this the 5-hour quota.
    case fiveHour
    /// Coding model's weekly quota.
    case week

    var usedKey: String {
        switch self {
        case .fiveHour: return "current_interval_used_percent"
        case .week: return "current_weekly_used_percent"
        }
    }

    var totalKey: String {
        switch self {
        case .fiveHour: return "current_interval_total_percent"
        case .week: return "current_weekly_total_percent"
        }
    }

    var startKey: String {
        switch self {
        case .fiveHour: return "start_time"
        case .week: return "weekly_start_time"
        }
    }

    var endKey: String {
        switch self {
        case .fiveHour: return "end_time"
        case .week: return "weekly_end_time"
        }
    }
}

public enum MiniMaxUsageDecoder {
    public enum Failure: Error, Equatable {
        case malformed
        case signedOut
        case noAllowance
        case rejected
        case missingUsage
        case missingReset
    }

    /// `GET /backend/account/token_plan/remains_percent`.
    /// Used percent is `used / total` on a 0...100 scale. The fields may be numbers or `4%` strings.
    /// A missing total is 100, matching the MiniMax client. The cycle is the window's start and end,
    /// unix milliseconds. Only `model_name == general` is the coding meter.
    public static func decode(_ data: Data, window: MiniMaxWindow) throws -> DashboardUsageReading {
        let json = try jsonObject(from: data)
        try validate(json)
        guard let item = generalItem(in: json) else {
            throw Failure.noAllowance
        }
        let used = try usedPercent(in: item, window: window)
        guard
            let start = UsageMath.parseCycleEnd(present(item[window.startKey])),
            let end = UsageMath.parseCycleEnd(present(item[window.endKey])),
            end > start
        else {
            throw Failure.missingReset
        }
        return DashboardUsageReading(usedPercent: used, cycleStart: start, cycleEnd: end)
    }

    private static func validate(_ json: [String: Any]) throws {
        guard let base = json["base_resp"] as? [String: Any] else { return }
        guard let code = UsageMath.doubleValue(base["status_code"]) else { return }
        if code == 0 { return }
        switch Int(code) {
        case 1004, 1016:
            throw Failure.signedOut
        case 2062:
            throw Failure.noAllowance
        default:
            throw Failure.rejected
        }
    }

    private static func generalItem(in json: [String: Any]) -> [String: Any]? {
        let items = json["model_remains"] as? [[String: Any]] ?? []
        return items.first { ($0["model_name"] as? String) == "general" }
    }

    private static func usedPercent(in item: [String: Any], window: MiniMaxWindow) throws -> Double {
        guard let used = percentValue(item[window.usedKey]) else {
            throw Failure.missingUsage
        }
        let total = percentValue(item[window.totalKey]) ?? 100
        guard used.isFinite, total.isFinite, total > 0 else {
            throw Failure.missingUsage
        }
        return used / total * 100
    }

    /// `"4%"` and `4` are both 4. A fraction such as `0.04` stays 0.04 so the caller can scale it.
    private static func percentValue(_ value: Any?) -> Double? {
        if let text = value as? String {
            var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasSuffix("%") {
                trimmed = String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces)
            }
            return Double(trimmed)
        }
        return UsageMath.doubleValue(value)
    }
}

private func jsonObject(from data: Data) throws -> [String: Any] {
    let object: Any
    do {
        object = try JSONSerialization.jsonObject(with: data)
    } catch {
        throw MiniMaxUsageDecoder.Failure.malformed
    }
    guard let json = object as? [String: Any] else {
        throw MiniMaxUsageDecoder.Failure.malformed
    }
    return json
}

private func present(_ value: Any?) -> Any? {
    if value == nil || value is NSNull {
        return nil
    }
    return value
}
