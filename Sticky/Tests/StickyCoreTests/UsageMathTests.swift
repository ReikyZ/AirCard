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

    func testResetDaysUsesLocalCalendarDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, zone: TimeZone? = nil) -> Date {
            var parts = DateComponents()
            parts.calendar = calendar
            parts.timeZone = zone ?? calendar.timeZone
            parts.year = year
            parts.month = month
            parts.day = day
            parts.hour = hour
            parts.minute = minute
            return calendar.date(from: parts)!
        }

        let now = date(2026, 10, 15, 15, 40)
        let laterToday = date(2026, 10, 15, 23, 0)
        let nextLocalDayStillSameUTCDate = date(2026, 10, 15, 16, 30, zone: TimeZone(secondsFromGMT: 0))
        let inThree = date(2026, 10, 18, 1, 0)

        XCTAssertEqual(UsageMath.resetDays(cycleEnd: laterToday, now: now, calendar: calendar), 0)
        XCTAssertEqual(UsageMath.resetDays(cycleEnd: nextLocalDayStillSameUTCDate, now: now, calendar: calendar), 1)
        XCTAssertEqual(UsageMath.resetDays(cycleEnd: inThree, now: now, calendar: calendar), 3)
        XCTAssertEqual(UsageMath.resetDays(cycleEnd: now.addingTimeInterval(-3600), now: now, calendar: calendar), 0)
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
        XCTAssertEqual(UsageMath.dayLabel(resetDays: 3), "3 天")
        XCTAssertEqual(UsageMath.dayLabel(resetDays: 26), "26 天")
        XCTAssertEqual(UsageMath.dayLabel(resetDays: 30), "30 天")
    }

    func testTrackWidthScalesWithCycleLength() {
        let month = 31.0 * 86_400
        let week = 7.0 * 86_400
        let fraction = UsageMath.trackWidthFraction(cycleSeconds: week, longestSeconds: month)
        XCTAssertEqual(fraction, 7.0 / 31.0, accuracy: 0.000_000_1)
        XCTAssertLessThan(fraction, 0.25)
        XCTAssertEqual(UsageMath.trackWidthFraction(cycleSeconds: month, longestSeconds: month), 1)
        XCTAssertEqual(UsageMath.trackWidthFraction(cycleSeconds: 0, longestSeconds: month), 0)
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
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(UsageMath.resetDays(cycleEnd: try XCTUnwrap(parsedMilliseconds), now: now, calendar: utc), 26)

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
        XCTAssertEqual(StickyCopy.notConnected, "未接入")
        XCTAssertTrue(StickyRoster.pending.allSatisfy { $0.reason == "未接入" })
        let rows = StickyRoster.names.map {
            VendorSnapshot(name: $0, kind: .unavailable(reason: StickyCopy.notConnected))
        }
        XCTAssertEqual(VendorOrder.arrange(rows, order: ["Grok Bot", "Cursor"]).map(\.name), ["Grok Bot", "Cursor", "Grok", "Mimo"])
        XCTAssertEqual(VendorOrder.move("Cursor", in: StickyRoster.names, to: 2), ["Grok", "Mimo", "Cursor", "Grok Bot"])
    }
}
