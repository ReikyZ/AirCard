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
    /// Reads `planUsage.remaining`, `planUsage.limit`, and `billingCycleEnd`.
    /// `totalPercentUsed` and `displayMessage` are ignored on purpose.
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
        guard
            let remaining = UsageMath.doubleValue(plan["remaining"]),
            let limit = UsageMath.doubleValue(plan["limit"])
        else {
            throw PeriodUsageDecodeError.missingPlanUsage
        }
        let cycleValue = present(json["billingCycleEnd"]) ?? present(plan["billingCycleEnd"])
        guard let cycleEnd = UsageMath.parseCycleEnd(cycleValue) else {
            throw PeriodUsageDecodeError.missingCycleEnd
        }
        return PeriodUsageReading(remaining: remaining, limit: limit, cycleEnd: cycleEnd)
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
