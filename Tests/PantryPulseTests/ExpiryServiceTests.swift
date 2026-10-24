import Foundation
import Testing
@testable import PantryPulse

@MainActor
struct ExpiryServiceTests {
    @Test func calendarDaysAndMissingExpiry() throws {
        for zone in ["Asia/Colombo", "America/New_York"] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(identifier: zone))
            for month in [3, 11] {
                let now = try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: month == 3 ? 8 : 1, hour: 23, minute: 59)))
                let statuses: [PantryFreshness] = [.expired, .urgent, .urgent, .expiringSoon, .expiringSoon, .fresh]
                for (day, status) in zip(-1...4, statuses) {
                    let date = try #require(calendar.date(byAdding: .day, value: day, to: now))
                    let result = ExpiryService.assess(date, on: now, calendar: calendar)
                    #expect(result.daysRemaining == day)
                    #expect(result.freshness == status)
                }
                #expect(ExpiryService.assess(nil, on: now, calendar: calendar).freshness == .unknown)
                #expect(ExpiryService.assess(now, on: now.addingTimeInterval(120), calendar: calendar).freshness == .expired)
            }
        }
    }

    @Test func changingTimeZoneReassessesLocalDay() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        var colombo = utc
        colombo.timeZone = try #require(TimeZone(identifier: "Asia/Colombo"))
        let now = try #require(utc.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 20)))
        let expiry = now.addingTimeInterval(-4 * 3600)
        #expect(ExpiryService.assess(expiry, on: now, calendar: utc).daysRemaining == 0)
        #expect(ExpiryService.assess(expiry, on: now, calendar: colombo).daysRemaining == -1)
    }
}
