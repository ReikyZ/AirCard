import XCTest
@testable import StickyCore

final class UsageMathTests: XCTestCase {
    func testRemainingFractionPrefersRemainingOverLimit() throws {
        let fraction = UsageMath.remainingFraction(remaining: 3400, limit: 10_000)
        XCTAssertEqual(fraction, 0.34)
        XCTAssertEqual(UsageMath.percentPoints(fraction: try XCTUnwrap(fraction)), 34)
    }

    func testPercentClampsToDisplayedRange() {
        XCTAssertEqual(UsageMath.percentPoints(fraction: 0), 0)
        XCTAssertEqual(UsageMath.percentPoints(fraction: 1), 100)
        XCTAssertEqual(UsageMath.percentPoints(fraction: 1.4), 100)
        XCTAssertEqual(UsageMath.percentPoints(fraction: -0.2), 0)
    }

    func testZeroOrNegativeLimitCannotInventAPercent() {
        XCTAssertNil(UsageMath.remainingFraction(remaining: 10, limit: 0))
        XCTAssertNil(UsageMath.remainingFraction(remaining: 10, limit: -5))
        XCTAssertNil(UsageMath.remainingFraction(remaining: .nan, limit: 10))
    }

    func testFractionClampsOverflowAndNegativeRemaining() {
        XCTAssertEqual(UsageMath.remainingFraction(remaining: 50, limit: 10), 1)
        XCTAssertEqual(UsageMath.remainingFraction(remaining: -4, limit: 10), 0)
    }

    func testResetDaysCeilsPartialDaysAndClampsThePast() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(UsageMath.resetDays(cycleEnd: now.addingTimeInterval(3 * 86_400), now: now), 3)
        XCTAssertEqual(UsageMath.resetDays(cycleEnd: now.addingTimeInterval(3 * 86_400 + 10), now: now), 4)
        XCTAssertEqual(UsageMath.resetDays(cycleEnd: now.addingTimeInterval(2 * 3_600), now: now), 1)
        XCTAssertEqual(UsageMath.resetDays(cycleEnd: now, now: now), 0)
        XCTAssertEqual(UsageMath.resetDays(cycleEnd: now.addingTimeInterval(-86_400), now: now), 0)
    }

    func testDayLabels() {
        XCTAssertEqual(UsageMath.dayLabel(resetDays: 0), "今天")
        XCTAssertEqual(UsageMath.dayLabel(resetDays: -2), "今天")
        XCTAssertEqual(UsageMath.dayLabel(resetDays: 3), "3天")
        XCTAssertEqual(UsageMath.dayLabel(resetDays: 26), "26天")
        XCTAssertEqual(UsageMath.dayLabel(resetDays: 30), "30天")
    }

    func testBarLengthUsesThirtyDaysAsFullTrack() {
        XCTAssertEqual(UsageMath.barLengthFraction(resetDays: 0), 0)
        XCTAssertEqual(UsageMath.barLengthFraction(resetDays: 3), 0.1, accuracy: 0.0001)
        XCTAssertEqual(UsageMath.barLengthFraction(resetDays: 26), 26.0 / 30.0, accuracy: 0.0001)
        XCTAssertEqual(UsageMath.barLengthFraction(resetDays: 30), 1)
        XCTAssertEqual(UsageMath.barLengthFraction(resetDays: 45), 1)
    }

    func testEpochMillisecondsStringAndUnixSeconds() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let end = now.addingTimeInterval(26 * 86_400)
        let milliseconds = String(Int(end.timeIntervalSince1970 * 1000))
        let parsedMilliseconds = UsageMath.parseCycleEnd(milliseconds)
        XCTAssertEqual(parsedMilliseconds?.timeIntervalSince1970 ?? -1, end.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(UsageMath.resetDays(cycleEnd: try XCTUnwrap(parsedMilliseconds), now: now), 26)

        let parsedSeconds = UsageMath.parseCycleEnd(end.timeIntervalSince1970)
        XCTAssertEqual(parsedSeconds?.timeIntervalSince1970 ?? -1, end.timeIntervalSince1970, accuracy: 0.001)
    }

    func testISO8601Dates() {
        let parsed = UsageMath.parseCycleEnd("2026-10-15T00:00:00Z")
        let fractional = UsageMath.parseCycleEnd("2026-10-15T00:00:00.000Z")
        XCTAssertEqual(parsed, fractional)
        XCTAssertNotNil(UsageMath.parseCycleEnd("2026-10-15"))
        XCTAssertNotNil(UsageMath.parseCycleEnd("2026-10-15T08:00:00+08:00"))
    }

    func testTokenNormalizeStripsWrappingQuotes() {
        XCTAssertEqual(TokenText.normalize("  abc  "), "abc")
        XCTAssertEqual(TokenText.normalize("\"eyJhbGci\""), "eyJhbGci")
        XCTAssertEqual(TokenText.normalize("\"  eyJ  \""), "eyJ")
        XCTAssertEqual(TokenText.normalize(""), "")
    }

    func testRosterOrderAndCaption() {
        XCTAssertEqual(StickyRoster.names, ["Cursor", "Grok", "Mimo", "Grok Bot"])
        XCTAssertEqual(StickyCopy.caption, "条长是剩余天数，填充是已用比例")
        XCTAssertEqual(StickyCopy.notConnected, "未接入")
        XCTAssertTrue(StickyRoster.pending.allSatisfy { $0.reason == "未接入" })
    }
}
