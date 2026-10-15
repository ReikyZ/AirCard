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

    /// Remaining percent after a used percent on the 0...100 scale.
    public static func remainingPercent(usedPercent: Double) -> Double {
        guard usedPercent.isFinite else { return 0 }
        return min(100, max(0, 100 - usedPercent))
    }

    /// Local calendar days from `now` until `cycleEnd`. The instants are absolute;
    /// `calendar` (the Mac clock by default) decides which civil day they fall on.
    /// A reset later today is 0, which the note shows as「今天」.
    public static func resetDays(cycleEnd: Date, now: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: now)
        let end = calendar.startOfDay(for: cycleEnd)
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return max(0, days)
    }

    public static func dayLabel(resetDays: Int) -> String {
        let days = max(0, resetDays)
        if days == 0 { return "今天" }
        return "\(days) 天"
    }

    /// Share of the longest cycle. A 7-day cycle next to a 31-day cycle is 7/31 of that track.
    public static func trackWidthFraction(cycleSeconds: Double, longestSeconds: Double) -> Double {
        guard cycleSeconds.isFinite, longestSeconds.isFinite, cycleSeconds > 0, longestSeconds > 0 else {
            return 0
        }
        return min(1, cycleSeconds / longestSeconds)
    }

    /// Share of this cycle still ahead: `(end - now) / (end - start)`, clamped to 0...1.
    /// Drawn as the left segment. It does not change how long the track is.
    public static func cycleRemainingFraction(start: Date, end: Date, now: Date) -> Double {
        let span = end.timeIntervalSince(start)
        guard span > 0, span.isFinite else { return 0 }
        let remaining = end.timeIntervalSince(now)
        guard remaining.isFinite else { return 0 }
        return min(1, max(0, remaining / span))
    }

    /// Share of this cycle already past: `(now - start) / (end - start)`, clamped to 0...1.
    /// Drawn as the right segment.
    public static func cycleElapsedFraction(start: Date, end: Date, now: Date) -> Double {
        let span = end.timeIntervalSince(start)
        guard span > 0, span.isFinite else { return 0 }
        let elapsed = now.timeIntervalSince(start)
        guard elapsed.isFinite else { return 0 }
        return min(1, max(0, elapsed / span))
    }

    /// The day label sits in the longer time segment, against the split.
    /// The right (elapsed) segment holds it only when that side is strictly longer.
    public static func dayLabelInElapsedSegment(elapsed: Double) -> Bool {
        guard elapsed.isFinite else { return false }
        let clamped = min(1, max(0, elapsed))
        return clamped > (1 - clamped)
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
        if hasExplicitTimeZone(text) {
            return parseISO8601(text)
        }
        // Xiaomi's plan window is a civil time with no zone, ending at 23:59:59.
        return parseChinaCivilTime(text) ?? parseISO8601(text)
    }

    static func hasExplicitTimeZone(_ text: String) -> Bool {
        if text.hasSuffix("Z") || text.hasSuffix("z") { return true }
        let tail = text.suffix(6)
        if tail.count == 6, let sign = tail.first, sign == "+" || sign == "-" {
            let chars = Array(tail.dropFirst())
            if chars.count == 5, chars[2] == ":", chars.allSatisfy({ $0 == ":" || $0.isNumber }) {
                return true
            }
        }
        let compact = text.suffix(5)
        if compact.count == 5, let sign = compact.first, sign == "+" || sign == "-" {
            return compact.dropFirst().allSatisfy(\.isNumber)
        }
        return false
    }

    /// `yyyy-MM-dd'T'HH:mm:ss` and `yyyy-MM-dd HH:mm:ss` as Asia/Shanghai wall time.
    static func parseChinaCivilTime(_ text: String) -> Date? {
        let zone = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone(secondsFromGMT: 8 * 3600)
        guard let zone else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) {
                return date
            }
        }
        return nil
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
