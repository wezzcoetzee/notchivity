import Testing

@testable import NotchivityKit

struct TimeFormattingTests {
    @Test func countdownPicksTheTwoLargestUnits() {
        let cases: [(Int, String)] = [
            (-5, "now"), (0, "now"), (30, "<1m"), (3599, "59m"),
            (3600, "1h 0m"), (86_399, "23h 59m"), (4 * 86_400 + 8 * 3600 + 59 * 60, "4d 8h"),
        ]
        for (seconds, text) in cases {
            #expect(TimeFormatting.countdown(secondsRemaining: seconds) == text)
        }
    }

    @Test func freshnessSwitchesToDaysAfterTwoDays() {
        let cases: [(Int, String)] = [
            (-10, "updated 0s ago"), (59, "updated 59s ago"), (60, "updated 1m ago"),
            (3600, "updated 1h ago"), (48 * 3600 - 1, "updated 47h ago"), (48 * 3600, "updated 2d ago"),
        ]
        for (seconds, text) in cases {
            #expect(TimeFormatting.freshness(secondsAgo: seconds) == text)
        }
    }
}
