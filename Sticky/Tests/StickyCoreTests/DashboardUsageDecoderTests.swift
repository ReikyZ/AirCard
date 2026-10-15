import XCTest
@testable import StickyCore

final class DashboardUsageDecoderTests: XCTestCase {
    func testCursorAutoPercentAboveOneStaysOnPercentScale() throws {
        let json = """
        {
          "billingCycleStart": "1791888228000",
          "billingCycleEnd": "1794566628000",
          "planUsage": { "autoPercentUsed": 8.188333333333334 }
        }
        """.data(using: .utf8)!

        let reading = try CursorPeriodUsageDecoder.decode(json)
        XCTAssertEqual(reading.usedPercent, 8.188333333333334, accuracy: 0.000_000_1)
        XCTAssertEqual(reading.cycleStart.timeIntervalSince1970, 1_791_888_228, accuracy: 0.001)
        XCTAssertEqual(reading.cycleEnd.timeIntervalSince1970, 1_794_566_628, accuracy: 0.001)
        XCTAssertEqual(UsageMath.remainingPercent(usedPercent: reading.usedPercent), 91.81166666666667, accuracy: 0.000_000_1)
        XCTAssertEqual(UsageMath.percentPoints(fraction: UsageMath.remainingPercent(usedPercent: reading.usedPercent) / 100), 92)
    }

    func testCursorFractionAutoPercentIsScaledToPercent() throws {
        let json = """
        {
          "billingCycleStart": "1690000000000",
          "billingCycleEnd": "1700000000000",
          "planUsage": { "autoPercentUsed": 0.25 }
        }
        """.data(using: .utf8)!

        let reading = try CursorPeriodUsageDecoder.decode(json)
        XCTAssertEqual(reading.usedPercent, 25, accuracy: 0.000_000_1)
        XCTAssertEqual(UsageMath.percentPoints(fraction: reading.usedPercent / 100), 25)
    }

    func testCursorOnePointZeroIsAlreadyOnePercent() throws {
        let json = """
        {"billingCycleStart": "1690000000000", "billingCycleEnd": "1700000000000", "planUsage": {"autoPercentUsed": 1}}
        """.data(using: .utf8)!
        let reading = try CursorPeriodUsageDecoder.decode(json)
        XCTAssertEqual(reading.usedPercent, 1, accuracy: 0.000_000_1)
    }

    func testCursorMissingAutoPercentDoesNotInventUsage() {
        let json = """
        {"billingCycleStart": "1690000000000", "billingCycleEnd": "1700000000000", "planUsage": {"totalPercentUsed": 40}}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try CursorPeriodUsageDecoder.decode(json)) { error in
            XCTAssertEqual(error as? DashboardUsageDecodeError, .missingUsage)
        }
    }

    func testGrokBotUsagePercentAndCycle() throws {
        let json = """
        {
          "usagePercent": 63.733165,
          "currentPeriodStart": "2026-10-09T04:05:27.046Z",
          "nextResetTimestampUtc": "2026-10-16T04:05:27.046Z"
        }
        """.data(using: .utf8)!

        let reading = try GrokSandUsageDecoder.decode(json)
        XCTAssertEqual(reading.usedPercent, 63.733165, accuracy: 0.000_000_1)
        XCTAssertEqual(UsageMath.remainingPercent(usedPercent: reading.usedPercent), 36.266835, accuracy: 0.000_000_1)
        XCTAssertEqual(UsageMath.percentPoints(fraction: UsageMath.remainingPercent(usedPercent: reading.usedPercent) / 100), 36)
        let start = try XCTUnwrap(UsageMath.parseCycleEnd("2026-10-09T04:05:27.046Z"))
        let end = try XCTUnwrap(UsageMath.parseCycleEnd("2026-10-16T04:05:27.046Z"))
        XCTAssertEqual(reading.cycleStart.timeIntervalSince1970, start.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(reading.cycleEnd.timeIntervalSince1970, end.timeIntervalSince1970, accuracy: 0.001)
        let midpoint = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
        XCTAssertEqual(UsageMath.cycleRemainingFraction(start: reading.cycleStart, end: reading.cycleEnd, now: midpoint), 0.5, accuracy: 0.000_000_1)
    }

    func testMalformedDashboardBody() {
        XCTAssertThrowsError(try CursorPeriodUsageDecoder.decode(Data("not-json".utf8))) { error in
            XCTAssertEqual(error as? DashboardUsageDecodeError, .malformed)
        }
        XCTAssertThrowsError(try GrokSandUsageDecoder.decode(Data("{}".utf8))) { error in
            XCTAssertEqual(error as? DashboardUsageDecodeError, .missingUsage)
        }
    }
}
