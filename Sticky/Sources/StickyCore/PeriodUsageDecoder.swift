import Foundation

public struct PeriodUsageReading: Equatable, Sendable {
    public var remaining: Double
    public var limit: Double
    public var cycleEnd: Date

    public init(remaining: Double, limit: Double, cycleEnd: Date) {
        self.remaining = remaining
        self.limit = limit
        self.cycleEnd = cycleEnd
    }
}

public enum PeriodUsageDecodeError: Error, Equatable {
    case malformed
    case missingPlanUsage
    case missingCycleEnd
}

public enum PeriodUsageDecoder {
    /// Reads `planUsage.limit` and a remaining amount, plus `billingCycleEnd`.
    /// A present `planUsage.remaining` wins. When it is absent, remaining is
    /// `limit - includedSpend`, then `limit - totalSpend`, then
    /// `limit * (1 - totalPercentUsed / 100)`. `displayMessage` is still ignored.
    /// Top-level `billingCycleEnd` is preferred over the nested value.
    public static func decode(_ data: Data) throws -> PeriodUsageReading {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw PeriodUsageDecodeError.malformed
        }
        guard let json = object as? [String: Any] else {
            throw PeriodUsageDecodeError.malformed
        }
        guard let plan = json["planUsage"] as? [String: Any] else {
            throw PeriodUsageDecodeError.missingPlanUsage
        }
        guard let limit = UsageMath.doubleValue(plan["limit"]) else {
            throw PeriodUsageDecodeError.missingPlanUsage
        }
        guard let remaining = remaining(in: plan, limit: limit) else {
            throw PeriodUsageDecodeError.missingPlanUsage
        }
        let cycleValue = present(json["billingCycleEnd"]) ?? present(plan["billingCycleEnd"])
        guard let cycleEnd = UsageMath.parseCycleEnd(cycleValue) else {
            throw PeriodUsageDecodeError.missingCycleEnd
        }
        return PeriodUsageReading(remaining: remaining, limit: limit, cycleEnd: cycleEnd)
    }

    /// `remaining` is optional on the live dashboard payload. Spend and percent
    /// fields are only used when it is missing, so an explicit remaining still wins.
    private static func remaining(in plan: [String: Any], limit: Double) -> Double? {
        if let remaining = UsageMath.doubleValue(plan["remaining"]) {
            return remaining
        }
        if let includedSpend = UsageMath.doubleValue(plan["includedSpend"]) {
            return limit - includedSpend
        }
        if let totalSpend = UsageMath.doubleValue(plan["totalSpend"]) {
            return limit - totalSpend
        }
        if let totalPercentUsed = UsageMath.doubleValue(plan["totalPercentUsed"]) {
            let fraction = 1 - totalPercentUsed / 100
            return limit * fraction
        }
        return nil
    }

    private static func present(_ value: Any?) -> Any? {
        if value == nil || value is NSNull {
            return nil
        }
        return value
    }
}

extension UsageMath {
    static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let number as Double:
            return number
        case let number as Int:
            return Double(number)
        case let number as NSNumber:
            return number.doubleValue
        case let text as String:
            return Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }
}
