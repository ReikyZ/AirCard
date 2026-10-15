import Foundation

public enum UsageMath {
    /// Remaining usage as a fraction of the plan limit.
    ///
    /// Both values are cents. `planUsage.totalPercentUsed` is the percent already
    /// used, so it is not the remaining percent. `displayMessage` can disagree
    /// with these numbers; prefer remaining/limit.
    public static func remainingFraction(remaining: Double, limit: Double) -> Double? {
        guard limit > 0, remaining.isFinite, limit.isFinite else { return nil }
        return min(1, max(0, remaining / limit))
    }

    public static func percentPoints(fraction: Double) -> Int {
        let clamped = min(1, max(0, fraction))
        return Int((clamped * 100).rounded(.toNearestOrAwayFromZero))
    }

    /// Days until `cycleEnd`, rounded up. A partial day still counts as one day.
    /// Results at or before `now` clamp to 0, which the note shows as「今天」.
    ///
    /// Current X Subscription pools refresh weekly, and `billingCycleEnd` can be
    /// the billing date rather than the weekly usage reset. Use `billingCycleEnd` for now.
    public static func resetDays(cycleEnd: Date, now: Date) -> Int {
        let days = cycleEnd.timeIntervalSince(now) / 86_400
        if days <= 0 { return 0 }
        return Int(ceil(days - 1e-6))
    }

    public static func dayLabel(resetDays: Int) -> String {
        let days = max(0, resetDays)
        if days == 0 { return "今天" }
        return "\(days)天"
    }

    /// Bar length as a fraction of the track. 30 days is the full track; longer cycles stay full.
    public static func barLengthFraction(resetDays: Int) -> Double {
        Double(min(max(resetDays, 0), 30)) / 30
    }

    /// Accepts unix milliseconds, unix seconds, or ISO-8601. Millisecond values may be strings.
    public static func parseCycleEnd(_ value: Any?) -> Date? {
        if let date = date(fromNumeric: value) {
            return date
        }
        if let text = value as? String {
            return parseCycleEndString(text)
        }
        return nil
    }

    public static func parseCycleEndString(_ raw: String) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        if looksNumeric(text), let number = Double(text) {
            return date(fromEpoch: number)
        }
        return parseISO8601(text)
    }

    static func date(fromNumeric value: Any?) -> Date? {
        let number: Double?
        switch value {
        case let numberValue as Double:
            number = numberValue
        case let numberValue as Int:
            number = Double(numberValue)
        case let numberValue as NSNumber:
            number = numberValue.doubleValue
        default:
            number = nil
        }
        guard let number else { return nil }
        return date(fromEpoch: number)
    }

    /// Values at or above 1e11 are unix milliseconds. Values at or above 1e8 are unix seconds.
    static func date(fromEpoch value: Double) -> Date? {
        guard value.isFinite, value > 0 else { return nil }
        if value >= 100_000_000_000 {
            return Date(timeIntervalSince1970: value / 1000)
        }
        if value >= 100_000_000 {
            return Date(timeIntervalSince1970: value)
        }
        return nil
    }

    static func looksNumeric(_ text: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "0123456789.-")
        return text.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    static func parseISO8601(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) {
            return date
        }
        let internet = ISO8601DateFormatter()
        internet.formatOptions = [.withInternetDateTime]
        if let date = internet.date(from: text) {
            return date
        }
        let day = ISO8601DateFormatter()
        day.formatOptions = [.withFullDate]
        return day.date(from: text)
    }
}
