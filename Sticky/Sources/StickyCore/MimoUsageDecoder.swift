import Foundation

public enum MimoUsageDecoder {
    /// Active token plan is the `plan_total_token` item under `data.usage.items`.
    /// Used percent is `used / limit` on a 0...100 scale.
    public static func decodeUsage(_ data: Data) throws -> Double {
        let json = try jsonObject(from: data)
        guard succeeds(json) else {
            throw DashboardUsageDecodeError.missingUsage
        }
        guard let item = activePlanItem(in: json) else {
            throw DashboardUsageDecodeError.missingUsage
        }
        guard
            let used = UsageMath.doubleValue(item["used"]),
            let limit = UsageMath.doubleValue(item["limit"]),
            used.isFinite, limit.isFinite, limit > 0
        else {
            throw DashboardUsageDecodeError.missingUsage
        }
        return used / limit * 100
    }

    /// Active plan window from `tokenPlan/current`: `currentPeriodStart` to `currentPeriodEnd`.
    public static func decodeCycle(_ data: Data) throws -> (start: Date, end: Date) {
        let json = try jsonObject(from: data)
        guard succeeds(json) else {
            throw DashboardUsageDecodeError.missingReset
        }
        let payload = (json["data"] as? [String: Any]) ?? json
        guard
            let start = UsageMath.parseCycleEnd(present(payload["currentPeriodStart"])),
            let end = UsageMath.parseCycleEnd(present(payload["currentPeriodEnd"]))
        else {
            throw DashboardUsageDecodeError.missingReset
        }
        return (start, end)
    }

    private static func activePlanItem(in json: [String: Any]) -> [String: Any]? {
        let items = usageItems(in: json)
        if let plan = items.first(where: { ($0["name"] as? String) == "plan_total_token" }) {
            return plan
        }
        return items.first { item in
            let name = item["name"] as? String
            let limit = UsageMath.doubleValue(item["limit"]) ?? 0
            return name != "compensation_total_token" && limit > 0
        }
    }

    private static func usageItems(in json: [String: Any]) -> [[String: Any]] {
        let payload = (json["data"] as? [String: Any]) ?? json
        let usage = (payload["usage"] as? [String: Any]) ?? payload
        return usage["items"] as? [[String: Any]] ?? []
    }

    private static func succeeds(_ json: [String: Any]) -> Bool {
        guard let code = UsageMath.doubleValue(json["code"]) else { return true }
        return code == 0
    }
}

private func jsonObject(from data: Data) throws -> [String: Any] {
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
