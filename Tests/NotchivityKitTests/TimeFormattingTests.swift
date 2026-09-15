import Testing
@testable import NotchivityKit

struct TimeFormattingTests {
    @Test func countdownResettingAtOrBelowZero() {
        #expect(TimeFormatting.countdown(secondsRemaining: 0) == "resetting…")
        #expect(TimeFormatting.countdown(secondsRemaining: -5) == "resetting…")
    }

    @Test func countdownMinutesOnly() {
        #expect(TimeFormatting.countdown(secondsRemaining: 60) == "1m")
        #expect(TimeFormatting.countdown(secondsRemaining: 3599) == "59m")
    }

    @Test func countdownHoursAndMinutes() {
        #expect(TimeFormatting.countdown(secondsRemaining: 3600) == "1h 0m")
        #expect(TimeFormatting.countdown(secondsRemaining: 86_399) == "23h 59m")
    }

    @Test func countdownDaysAndHours() {
        #expect(TimeFormatting.countdown(secondsRemaining: 86_400) == "1d 0h")
        #expect(TimeFormatting.countdown(secondsRemaining: 4 * 86_400 + 8 * 3600 + 59 * 60) == "4d 8h")
    }

    @Test func freshnessSeconds() {
        #expect(TimeFormatting.freshness(secondsAgo: 0) == "updated 0s ago")
        #expect(TimeFormatting.freshness(secondsAgo: 59) == "updated 59s ago")
        #expect(TimeFormatting.freshness(secondsAgo: -10) == "updated 0s ago")
    }

    @Test func freshnessMinutesThenHours() {
        #expect(TimeFormatting.freshness(secondsAgo: 60) == "updated 1m ago")
        #expect(TimeFormatting.freshness(secondsAgo: 3599) == "updated 59m ago")
        #expect(TimeFormatting.freshness(secondsAgo: 3600) == "updated 1h ago")
    }
}
