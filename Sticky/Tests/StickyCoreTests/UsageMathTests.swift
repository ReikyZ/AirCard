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

    func testResetDaysCountsWholeDaysAndClampsThePast() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(UsageMath.resetDays(cycleEnd: now.addingTimeInterval(3 * 86_400), now: now), 3)
        XCTAssertEqual(UsageMath.resetDays(cycleEnd: now.addingTimeInterval(3 * 86_400 + 10), now: now), 3)
        XCTAssertEqual(UsageMath.resetDays(cycleEnd: now.addingTimeInterval(2 * 3_600), now: now), 0)
        XCTAssertEqual(UsageMath.resetDays(cycleEnd: now, now: now), 0)
        XCTAssertEqual(UsageMath.resetDays(cycleEnd: now.addingTimeInterval(-86_400), now: now), 0)
    }

    func testRemainingPercentClampsUsedAmount() {
        XCTAssertEqual(UsageMath.remainingPercent(usedPercent: 8.188333333333334), 91.81166666666667, accuracy: 0.000_000_1)
        XCTAssertEqual(UsageMath.remainingPercent(usedPercent: 0), 100)
        XCTAssertEqual(UsageMath.remainingPercent(usedPercent: 100), 0)
        XCTAssertEqual(UsageMath.remainingPercent(usedPercent: 140), 0)
        XCTAssertEqual(UsageMath.remainingPercent(usedPercent: -10), 100)
        XCTAssertEqual(UsageMath.percentPoints(fraction: UsageMath.remainingPercent(usedPercent: 8.188333333333334) / 100), 92)
    }

    func testDayLabels() {
        XCTAssertEqual(UsageMath.dayLabel(resetDays: 0), "今天")
        XCTAssertEqual(UsageMath.dayLabel(resetDays: -2), "今天")
        XCTAssertEqual(UsageMath.dayLabel(resetDays: 3), "3天")
        XCTAssertEqual(UsageMath.dayLabel(resetDays: 26), "26天")
        XCTAssertEqual(UsageMath.dayLabel(resetDays: 30), "30天")
    }

    func testBarLengthIsRemainingFractionOfTheCycle() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = start.addingTimeInterval(10 * 86_400)
        let now = start.addingTimeInterval(4 * 86_400)
        XCTAssertEqual(UsageMath.cycleRemainingFraction(start: start, end: end, now: now), 0.6, accuracy: 0.000_000_1)
        XCTAssertEqual(UsageMath.cycleRemainingFraction(start: start, end: end, now: start.addingTimeInterval(-86_400)), 1)
        XCTAssertEqual(UsageMath.cycleRemainingFraction(start: start, end: end, now: end.addingTimeInterval(10)), 0)
        XCTAssertEqual(UsageMath.cycleRemainingFraction(start: end, end: end, now: end), 0)
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
        XCTAssertEqual(StickyCopy.caption, "条长是本周期剩余，填充是剩余用量")
        XCTAssertEqual(StickyCopy.notConnected, "未接入")
        XCTAssertTrue(StickyRoster.pending.allSatisfy { $0.reason == "未接入" })
    }
}
