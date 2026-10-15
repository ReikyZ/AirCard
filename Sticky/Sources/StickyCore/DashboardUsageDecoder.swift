import Foundation

public struct DashboardUsageReading: Equatable, Sendable {
    /// Used amount on a 0...100 scale, before display rounding.
    public var usedPercent: Double
    public var cycleStart: Date
    public var cycleEnd: Date

    public init(usedPercent: Double, cycleStart: Date, cycleEnd: Date) {
        self.usedPercent = usedPercent
        self.cycleStart = cycleStart
        self.cycleEnd = cycleEnd
    }
}

public enum DashboardUsageDecodeError: Error, Equatable {
    case malformed
    case missingUsage
    case missingReset
}

public enum UsagePercentScale {
    /// Fractions in (0, 1) are not yet percents. 0 and values that are already
    /// on a 0...100 scale, including 1, stay as they are.
    public static func usedPercent(from raw: Double) -> Double? {
        guard raw.isFinite else { return nil }
        if raw > 0, raw < 1 {
            return raw * 100
        }
        return raw
    }
}

public enum CursorPeriodUsageDecoder {
    /// `planUsage.autoPercentUsed` is the used percent. The cycle runs from
    /// `billingCycleStart` to `billingCycleEnd`.
    public static func decode(_ data: Data) throws -> DashboardUsageReading {
        let json = try object(from: data)
        guard
            let plan = json["planUsage"] as? [String: Any],
            let raw = UsageMath.doubleValue(plan["autoPercentUsed"]),
            let usedPercent = UsagePercentScale.usedPercent(from: raw)
        else {
            throw DashboardUsageDecodeError.missingUsage
        }
        guard
            let cycleStart = UsageMath.parseCycleEnd(present(json["billingCycleStart"])),
            let cycleEnd = UsageMath.parseCycleEnd(present(json["billingCycleEnd"]))
        else {
            throw DashboardUsageDecodeError.missingReset
        }
        return DashboardUsageReading(usedPercent: usedPercent, cycleStart: cycleStart, cycleEnd: cycleEnd)
    }
}

public enum GrokSandUsageDecoder {
    /// Sand usage belongs on the Grok Bot row. `usagePercent` is the used percent.
    /// The cycle runs from `currentPeriodStart` to `nextResetTimestampUtc`.
    public static func decode(_ data: Data) throws -> DashboardUsageReading {
        let json = try object(from: data)
        guard
            let raw = UsageMath.doubleValue(json["usagePercent"]),
            let usedPercent = UsagePercentScale.usedPercent(from: raw)
        else {
            throw DashboardUsageDecodeError.missingUsage
        }
        guard
            let cycleStart = UsageMath.parseCycleEnd(present(json["currentPeriodStart"])),
            let cycleEnd = UsageMath.parseCycleEnd(present(json["nextResetTimestampUtc"]))
        else {
            throw DashboardUsageDecodeError.missingReset
        }
        return DashboardUsageReading(usedPercent: usedPercent, cycleStart: cycleStart, cycleEnd: cycleEnd)
    }
}

private func object(from data: Data) throws -> [String: Any] {
    let object: Any
    do {
        object = try JSONSerialization.jsonObject(with: data)
    } catch {
        throw DashboardUsageDecodeError.malformed
    }
    guard let json = object as? [String: Any] else {
        throw DashboardUsageDecodeError.malformed
    }
    return json
}

private func present(_ value: Any?) -> Any? {
    if value == nil || value is NSNull {
        return nil
    }
    return value
}
