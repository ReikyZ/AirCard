import XCTest
@testable import StickyCore

final class PeriodUsageDecoderTests: XCTestCase {
    func testRemainingOverLimitIgnoresTotalPercentUsedAndDisplayMessage() throws {
        let json = """
        {
          "billingCycleEnd": "1702592000000",
          "displayMessage": "You've used 90% of your included usage",
          "planUsage": {
            "remaining": 3400,
            "limit": 10000,
            "totalPercentUsed": 90
          }
        }
        """.data(using: .utf8)!

        let reading = try PeriodUsageDecoder.decode(json)
        XCTAssertEqual(reading.remaining, 3400)
        XCTAssertEqual(reading.limit, 10000)
        XCTAssertEqual(reading.cycleEnd.timeIntervalSince1970, 1_702_592_000, accuracy: 0.001)

        let fraction = try XCTUnwrap(UsageMath.remainingFraction(remaining: reading.remaining, limit: reading.limit))
        XCTAssertEqual(UsageMath.percentPoints(fraction: fraction), 34)
        XCTAssertNotEqual(UsageMath.percentPoints(fraction: fraction), 10)
    }

    func testIncludedSpendWithoutRemaining() throws {
        let json = """
        {
          "billingCycleEnd": "1702592000000",
          "planUsage": {
            "limit": 10000,
            "includedSpend": 6600
          }
        }
        """.data(using: .utf8)!

        let reading = try PeriodUsageDecoder.decode(json)
        XCTAssertEqual(reading.remaining, 3400)
        XCTAssertEqual(reading.limit, 10000)
        XCTAssertEqual(reading.cycleEnd.timeIntervalSince1970, 1_702_592_000, accuracy: 0.001)

        let fraction = try XCTUnwrap(UsageMath.remainingFraction(remaining: reading.remaining, limit: reading.limit))
        XCTAssertEqual(UsageMath.percentPoints(fraction: fraction), 34)
    }

    func testStringAmountsAndCycleEndNestedOnPlanUsage() throws {
        let json = """
        {
          "planUsage": {
            "remaining": "50",
            "limit": "200",
            "billingCycleEnd": "2026-11-01T00:00:00Z"
          }
        }
        """.data(using: .utf8)!

        let reading = try PeriodUsageDecoder.decode(json)
        XCTAssertEqual(reading.remaining, 50)
        XCTAssertEqual(reading.limit, 200)
        XCTAssertEqual(
            reading.cycleEnd.timeIntervalSince1970,
            try XCTUnwrap(UsageMath.parseCycleEnd("2026-11-01T00:00:00Z")).timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func testUnixSecondsNumber() throws {
        let json = """
        {"planUsage": {"remaining": 1, "limit": 4}, "billingCycleEnd": 1700000000}
        """.data(using: .utf8)!

        let reading = try PeriodUsageDecoder.decode(json)
        XCTAssertEqual(reading.cycleEnd.timeIntervalSince1970, 1_700_000_000, accuracy: 0.001)
        let fraction = try XCTUnwrap(UsageMath.remainingFraction(remaining: reading.remaining, limit: reading.limit))
        XCTAssertEqual(UsageMath.percentPoints(fraction: fraction), 25)
    }

    func testNullTopLevelCycleEndFallsThroughToNestedValue() throws {
        let json = """
        {
          "billingCycleEnd": null,
          "planUsage": {"remaining": 1, "limit": 2, "billingCycleEnd": 1700000000}
        }
        """.data(using: .utf8)!
        let reading = try PeriodUsageDecoder.decode(json)
        XCTAssertEqual(reading.cycleEnd.timeIntervalSince1970, 1_700_000_000, accuracy: 0.001)
    }

    func testMissingPlanUsageDoesNotInventAPercent() {
        XCTAssertThrowsError(try PeriodUsageDecoder.decode(Data("{}".utf8))) { error in
            XCTAssertEqual(error as? PeriodUsageDecodeError, .missingPlanUsage)
        }
        let usedOnly = """
        {"totalPercentUsed": 12, "displayMessage": "12% used"}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try PeriodUsageDecoder.decode(usedOnly)) { error in
            XCTAssertEqual(error as? PeriodUsageDecodeError, .missingPlanUsage)
        }
    }

    func testMissingCycleEnd() {
        let json = """
        {"planUsage": {"remaining": 1, "limit": 2}}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try PeriodUsageDecoder.decode(json)) { error in
            XCTAssertEqual(error as? PeriodUsageDecodeError, .missingCycleEnd)
        }
    }

    func testMalformedBody() {
        XCTAssertThrowsError(try PeriodUsageDecoder.decode(Data("not-json".utf8))) { error in
            XCTAssertEqual(error as? PeriodUsageDecodeError, .malformed)
        }
    }
}
