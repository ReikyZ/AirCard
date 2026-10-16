import XCTest
@testable import StickyCore

final class MiniMaxUsageDecoderTests: XCTestCase {
    func testGeneralFiveHourAndWeekIgnoreVideo() throws {
        let five = try MiniMaxUsageDecoder.decode(Self.remains, window: .fiveHour)
        XCTAssertEqual(five.usedPercent, 0, accuracy: 0.000_000_1)
        XCTAssertEqual(five.cycleEnd.timeIntervalSince(five.cycleStart), 5 * 60 * 60, accuracy: 0.5)
        XCTAssertEqual(UsageMath.percentPoints(fraction: UsageMath.remainingPercent(usedPercent: five.usedPercent) / 100), 100)

        let week = try MiniMaxUsageDecoder.decode(Self.remains, window: .week)
        XCTAssertEqual(week.usedPercent, 4, accuracy: 0.000_000_1)
        XCTAssertEqual(week.cycleEnd.timeIntervalSince(week.cycleStart), 7 * 24 * 60 * 60, accuracy: 0.5)
        XCTAssertEqual(UsageMath.percentPoints(fraction: UsageMath.remainingPercent(usedPercent: week.usedPercent) / 100), 96)
    }

    func testUsedPercentIsScaledByTotal() throws {
        let json = """
        {
          "base_resp": {"status_code": 0, "status_msg": "success"},
          "model_remains": [{
            "model_name": "general",
            "current_interval_used_percent": 20,
            "current_interval_total_percent": 50,
            "start_time": 1792116000000,
            "end_time": 1792134000000
          }]
        }
        """.data(using: .utf8)!
        let reading = try MiniMaxUsageDecoder.decode(json, window: .fiveHour)
        XCTAssertEqual(reading.usedPercent, 40, accuracy: 0.000_000_1)
    }

    func testMissingGeneralIsNoAllowance() {
        let json = """
        {"base_resp":{"status_code":0},"model_remains":[{"model_name":"video","current_weekly_used_percent":"0%"}]}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try MiniMaxUsageDecoder.decode(json, window: .week)) { error in
            XCTAssertEqual(error as? MiniMaxUsageDecoder.Failure, .noAllowance)
        }
    }

    func testSignedOutAndNoPlan() {
        let signedOut = """
        {"base_resp":{"status_code":1004,"status_msg":"not login"}}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try MiniMaxUsageDecoder.decode(signedOut, window: .week)) { error in
            XCTAssertEqual(error as? MiniMaxUsageDecoder.Failure, .signedOut)
        }
        let invalid = """
        {"base_resp":{"status_code":1016,"status_msg":"invalid api key"}}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try MiniMaxUsageDecoder.decode(invalid, window: .fiveHour)) { error in
            XCTAssertEqual(error as? MiniMaxUsageDecoder.Failure, .signedOut)
        }
        let noPlan = """
        {"model_remains":null,"base_resp":{"status_code":2062,"status_msg":"no active token plan subscription"}}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try MiniMaxUsageDecoder.decode(noPlan, window: .week)) { error in
            XCTAssertEqual(error as? MiniMaxUsageDecoder.Failure, .noAllowance)
        }
    }

    func testMalformedBody() {
        XCTAssertThrowsError(try MiniMaxUsageDecoder.decode(Data("not-json".utf8), window: .fiveHour)) { error in
            XCTAssertEqual(error as? MiniMaxUsageDecoder.Failure, .malformed)
        }
    }

    private static let remains = """
    {
      "model_remains": [
        {
          "model_name": "general",
          "start_time": 1792116000000,
          "end_time": 1792134000000,
          "current_interval_used_percent": "0%",
          "current_interval_total_percent": "100%",
          "weekly_start_time": 1791734400000,
          "weekly_end_time": 1792339200000,
          "current_weekly_used_percent": "4%",
          "current_weekly_total_percent": "100%"
        },
        {
          "model_name": "video",
          "start_time": 1792080000000,
          "end_time": 1792166400000,
          "current_interval_used_percent": "0%",
          "current_interval_total_percent": "100%",
          "weekly_start_time": 1791734400000,
          "weekly_end_time": 1792339200000,
          "current_weekly_used_percent": "0%",
          "current_weekly_total_percent": "100%"
        }
      ],
      "base_resp": {"status_code": 0, "status_msg": "success"}
    }
    """.data(using: .utf8)!
}
