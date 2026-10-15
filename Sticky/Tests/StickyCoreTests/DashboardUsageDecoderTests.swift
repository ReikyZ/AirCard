import XCTest
@testable import StickyCore

final class DashboardUsageDecoderTests: XCTestCase {
    func testCursorAutoPercentAboveOneStaysOnPercentScale() throws {
        let json = """
        {
          "billingCycleEnd": "1794566628000",
          "planUsage": { "autoPercentUsed": 8.188333333333334 }
        }
        """.data(using: .utf8)!

        let reading = try CursorPeriodUsageDecoder.decode(json)
        XCTAssertEqual(reading.usedPercent, 8.188333333333334, accuracy: 0.000_000_1)
        XCTAssertEqual(reading.cycleEnd.timeIntervalSince1970, 1_794_566_628, accuracy: 0.001)

        let fraction = reading.usedPercent / 100
        XCTAssertEqual(UsageMath.percentPoints(fraction: fraction), 8)
    }

    func testCursorFractionAutoPercentIsScaledToPercent() throws {
        let json = """
        {
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
        {"billingCycleEnd": "1700000000000", "planUsage": {"autoPercentUsed": 1}}
        """.data(using: .utf8)!
        let reading = try CursorPeriodUsageDecoder.decode(json)
        XCTAssertEqual(reading.usedPercent, 1, accuracy: 0.000_000_1)
    }

    func testCursorMissingAutoPercentDoesNotInventUsage() {
        let json = """
        {"billingCycleEnd": "1700000000000", "planUsage": {"totalPercentUsed": 40}}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try CursorPeriodUsageDecoder.decode(json)) { error in
            XCTAssertEqual(error as? DashboardUsageDecodeError, .missingUsage)
        }
    }

    func testGrokUsagePercentAndResetTimestamp() throws {
        let json = """
        {
          "usagePercent": 63.733165,
          "nextResetTimestampUtc": "2026-10-16T04:05:27.046Z"
        }
        """.data(using: .utf8)!

        let reading = try GrokSandUsageDecoder.decode(json)
        XCTAssertEqual(reading.usedPercent, 63.733165, accuracy: 0.000_000_1)
        XCTAssertEqual(UsageMath.percentPoints(fraction: reading.usedPercent / 100), 64)
        XCTAssertEqual(
            reading.cycleEnd.timeIntervalSince1970,
            try XCTUnwrap(UsageMath.parseCycleEnd("2026-10-16T04:05:27.046Z")).timeIntervalSince1970,
            accuracy: 0.001
        )
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
