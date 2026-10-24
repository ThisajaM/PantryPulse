import CoreData
import SwiftUI
import Testing
@testable import PantryPulse

@MainActor
struct FreshnessPulseTests {
    private func distribution(_ model: PantryViewModel) -> FreshnessPulseDistribution {
        FreshnessPulseDistribution(fresh: model.freshCount, expiringSoon: model.expiringSoonCount,
                                   urgent: model.urgentCount, expired: model.expiredCount,
                                   unknown: model.unknownExpiryCount)
    }

    @Test func proportionsCoverEmptyPureMixedUnknownAndExpiredInventory() {
        let examples: [(Int, Int, Int, Int, Int, [Double])] = [
            (0, 0, 0, 0, 0, [1]), (1, 0, 0, 0, 0, [1]),
            (0, 0, 1, 0, 0, [1]), (1, 0, 1, 0, 0, [0.5, 0.5]),
            (2, 1, 0, 0, 0, [2.0 / 3, 1.0 / 3]), (0, 0, 0, 0, 1, [1]),
            (0, 0, 0, 1, 0, [1]), (1, 1, 1, 1, 1, [0.2, 0.2, 0.4, 0.2])
        ]
        for (fresh, soon, urgent, expired, unknown, widths) in examples {
            let result = FreshnessPulseDistribution(fresh: fresh, expiringSoon: soon, urgent: urgent, expired: expired, unknown: unknown)
            #expect(result.bands.first?.start == 0)
            #expect(result.bands.last?.end == 1)
            #expect(result.bands.count == widths.count)
            for (band, width) in zip(result.bands, widths) {
                #expect(abs(band.end - band.start - width) < 0.000001)
            }
            for pair in zip(result.bands, result.bands.dropFirst()) {
                #expect(pair.0.end == pair.1.start)
            }
        }
    }

    @Test func gaugeFollowsSavedMutationsDayChangesAndDiskReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("pulse.sqlite")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var clock = calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 12))!
        let storage = PersistenceController(storeURL: url)
        await storage.load()
        let container = try #require(storage.container)
        let repo = PantryRepository(container: container, now: { clock })
        let dashboard = PantryViewModel(repository: repo, now: { clock }, calendar: calendar)
        #expect(distribution(dashboard).bands.first?.category == .unknown)
        var fresh = FoodDraft(name: "Fresh")
        fresh.expiryDate = calendar.date(byAdding: .day, value: 4, to: clock)
        _ = try repo.create(fresh)
        #expect(distribution(dashboard).bands.first?.category == .fresh)
        var urgent = FoodDraft(name: "Urgent")
        urgent.expiryDate = clock
        _ = try repo.create(urgent)
        #expect(distribution(dashboard).bands.map(\.end) == [0.5, 1])
        urgent.expiryDate = nil
        _ = try repo.update(urgent)
        #expect(distribution(dashboard).bands.last?.category == .unknown)
        for status in [PantryItemStatus.consumed, .wasted] {
            urgent.status = status
            _ = try repo.update(urgent)
            #expect(dashboard.itemCount == 1)
            #expect(distribution(dashboard).bands.count == 1)
        }
        try repo.delete(id: urgent.id)
        clock = calendar.date(byAdding: .day, value: 2, to: clock)!
        dashboard.reload()
        #expect(distribution(dashboard).bands.first?.category == .expiringSoon)
        let expected = distribution(dashboard)
        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }
        let reopened = PersistenceController(storeURL: url)
        await reopened.load()
        let reopenedContainer = try #require(reopened.container)
        let restoredRepository = PantryRepository(container: reopenedContainer)
        let restored = PantryViewModel(repository: restoredRepository, now: { clock }, calendar: calendar)
        #expect(distribution(restored) == expected)
        try restoredRepository.delete(id: fresh.id)
        #expect(restored.itemCount == 0)
        #expect(distribution(restored).bands == [.init(category: .unknown, start: 0, end: 1)])
        for store in reopenedContainer.persistentStoreCoordinator.persistentStores {
            try reopenedContainer.persistentStoreCoordinator.remove(store)
        }
    }

    @Test func smallPhoneRenderingUsesActualGreenAndRedHalfArcs() throws {
        // Render only the real component, without injecting any fixtures into the running app.
        for (fresh, urgent, name) in [(0, 0, "empty"), (1, 0, "fresh"), (0, 1, "urgent"), (1, 1, "half")] {
            let renderer = ImageRenderer(content: PantrySummaryCard(total: fresh + urgent, fresh: fresh,
                expiringSoon: 0, urgent: urgent, expired: 0, unknownExpiry: 0, onAddFood: {})
                .frame(width: 311).environment(\.colorScheme, .light))
            renderer.scale = 1
            let image = try #require(renderer.uiImage)
            let cg = try #require(image.cgImage)
            let width = cg.width, height = cg.height
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            let context = try #require(CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            var green = 0, red = 0
            // Top 200 points contain the gauge, above the summary cards.
            for y in 0..<min(200, height) {
                for x in 0..<width {
                    let i = (y * width + x) * 4
                    if abs(Int(pixels[i]) - 120) < 4 && abs(Int(pixels[i + 1]) - 169) < 4 && abs(Int(pixels[i + 2]) - 107) < 4 { green += 1 }
                    if abs(Int(pixels[i]) - 201) < 4 && abs(Int(pixels[i + 1]) - 79) < 4 && abs(Int(pixels[i + 2]) - 79) < 4 { red += 1 }
                }
            }
            #expect(fresh > 0 ? green > 500 : green == 0)
            #expect(urgent > 0 ? red > 500 : red == 0)
            if fresh == 1 && urgent == 1 { #expect(abs(Double(green) / Double(green + red) - 0.5) < 0.05) }
            try #require(image.pngData()).write(to: FileManager.default.temporaryDirectory.appendingPathComponent("pulse-\(name).png"))
        }
    }
}
