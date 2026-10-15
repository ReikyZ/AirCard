import XCTest
@testable import StickyCore

final class MimoUsageDecoderTests: XCTestCase {
    func testActiveTokenPlanUsesUsedOverLimit() throws {
        let json = """
        {
          "code": 0,
          "data": {
            "monthUsage": {
              "percent": 0.2435,
              "items": [
                {"name": "month_total_token", "used": 5000, "limit": 10000, "percent": 0.5}
              ]
            },
            "usage": {
              "percent": 0.24,
              "items": [
                {"name": "compensation_total_token", "used": 0, "limit": 0, "percent": 0},
                {"name": "plan_total_token", "used": 2400, "limit": 10000, "percent": 0.24}
              ]
            }
          }
        }
        """.data(using: .utf8)!

        let used = try MimoUsageDecoder.decodeUsage(json)
        XCTAssertEqual(used, 24, accuracy: 0.000_000_1)
        let remaining = UsageMath.remainingPercent(usedPercent: used)
        XCTAssertEqual(UsageMath.percentPoints(fraction: remaining / 100), 76)
    }

    func testNamedPlanWinsOverAnotherPositiveLimit() throws {
        let json = """
        {
          "code": 0,
          "data": {
            "usage": {
              "items": [
                {"name": "other_bucket", "used": 100, "limit": 1000},
                {"name": "plan_total_token", "used": 2400, "limit": 10000}
              ]
            }
          }
        }
        """.data(using: .utf8)!
        XCTAssertEqual(try MimoUsageDecoder.decodeUsage(json), 24, accuracy: 0.000_000_1)
    }

    func testMissingPlanDoesNotInventUsage() {
        let json = """
        {"code": 0, "data": {"usage": {"items": [{"name": "compensation_total_token", "used": 0, "limit": 0}]}}}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try MimoUsageDecoder.decodeUsage(json)) { error in
            XCTAssertEqual(error as? DashboardUsageDecodeError, .missingUsage)
        }
    }

    func testCycleUsesPeriodStartAndEndAsLocalDays() throws {
        let json = """
        {
          "code": 0,
          "data": {
            "planCode": "lite",
            "currentPeriodStart": "2026-10-09T02:54:31",
            "currentPeriodEnd": "2026-11-09T23:59:59",
            "expired": false
          }
        }
        """.data(using: .utf8)!

        let cycle = try MimoUsageDecoder.decodeCycle(json)
        var china = Calendar(identifier: .gregorian)
        china.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        var startParts = DateComponents()
        startParts.calendar = china
        startParts.timeZone = china.timeZone
        startParts.year = 2026
        startParts.month = 10
        startParts.day = 9
        startParts.hour = 2
        startParts.minute = 54
        startParts.second = 31
        var endParts = startParts
        endParts.month = 11
        endParts.day = 9
        endParts.hour = 23
        endParts.minute = 59
        endParts.second = 59
        XCTAssertEqual(cycle.start.timeIntervalSince1970, china.date(from: startParts)!.timeIntervalSince1970, accuracy: 0.5)
        XCTAssertEqual(cycle.end.timeIntervalSince1970, china.date(from: endParts)!.timeIntervalSince1970, accuracy: 0.5)

        var nowParts = startParts
        nowParts.day = 15
        nowParts.hour = 16
        nowParts.minute = 0
        nowParts.second = 0
        let now = china.date(from: nowParts)!
        XCTAssertEqual(UsageMath.resetDays(cycleEnd: cycle.end, now: now, calendar: china), 25)
        XCTAssertEqual(UsageMath.dayLabel(resetDays: 25), "25天")
        let elapsed = UsageMath.cycleElapsedFraction(start: cycle.start, end: cycle.end, now: now)
        XCTAssertLessThan(elapsed, 0.5)
        XCTAssertFalse(UsageMath.dayLabelInElapsedSegment(elapsed: elapsed))
        let span = cycle.end.timeIntervalSince(cycle.start)
        XCTAssertGreaterThan(span, 31 * 86_400)
        XCTAssertLessThan(span, 33 * 86_400)
    }

    func testMalformedUsageBody() {
        XCTAssertThrowsError(try MimoUsageDecoder.decodeUsage(Data("not-json".utf8))) { error in
            XCTAssertEqual(error as? DashboardUsageDecodeError, .malformed)
        }
    }
}
