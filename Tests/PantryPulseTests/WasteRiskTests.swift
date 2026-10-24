import Foundation
import CoreML
import Testing
@testable import PantryPulse

@MainActor
struct WasteRiskTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private func item(days: Int = 3) -> PantryItem {
        PantryItem(id: UUID(), name: "Vegetables", category: .vegetables,
            storageLocation: "Fridge", expiryDate: calendar.date(byAdding: .day, value: days, to: now),
            quantity: 1.13, quantityUnit: .kilograms)
    }
    private func features(_ item: PantryItem, _ events: [UsageEvent] = []) throws -> WasteRiskFeatures {
        try WasteRiskFeatureBuilder.build(item: item, history: events, on: now, calendar: calendar)
    }
    private func event(_ type: UsageEventType, category: FoodCategory = .vegetables, date: Date? = nil) -> UsageEvent {
        UsageEvent(id: UUID(), itemID: UUID(), itemName: "Recorded food", category: category,
            type: type, quantity: 1, unit: .pieces, date: date ?? now)
    }

    @Test func schemaUsesRecordedValuesAndColdStart() throws {
        let f = try features(item())
        #expect(f.category == "Vegetables" && f.storageType == "Fridge")
        #expect(f.quantityValue == 1.13 && f.quantityUnit == "kg" && f.daysUntilExpiry == 3)
        #expect(f.historyEventCount == 0 && f.historicalWasteRate == 0)
        #expect(f.explanations.contains { $0.contains("cold-start") })
    }

    @Test func historyIsCategorySpecificBoundedAndNotQuantityBased() throws {
        var events = (1...35).map { index in event(.consumed, date: now.addingTimeInterval(Double(-index))) }
        events += [event(.wasted), event(.wasted, category: .dairy), event(.wasted, date: now.addingTimeInterval(60))]
        let f = try features(item(), events)
        #expect(f.historyEventCount == 30)
        #expect(abs(f.historicalWasteRate - 1.0 / 30) < 0.000001)
    }

    @Test func invalidOrUnsupportedInputsDoNotProduceRisk() {
        var missing = item(); missing.expiryDate = nil
        var quantity = item(); quantity.quantity = .nan
        var unit = item(); unit.quantityUnit = .bottles
        var storage = item(); storage.storageLocation = "Countertop"
        var category = item(); category.category = .snacks
        var inactive = item(); inactive.status = .consumed
        for value in [missing, quantity, unit, storage, category, inactive, item(days: -1), item(days: 121)] {
            #expect(throws: WasteRiskInputError.self) { try features(value) }
        }
    }

    @Test func calendarDayRefreshChangesFeaturesWithoutChangingStoredDate() throws {
        let value = item(days: 1)
        let next = try #require(calendar.date(byAdding: .day, value: 1, to: now))
        #expect(try features(value).daysUntilExpiry == 1)
        #expect(try WasteRiskFeatureBuilder.build(item: value, history: [], on: next, calendar: calendar).daysUntilExpiry == 0)
        let past = try #require(calendar.date(byAdding: .day, value: 2, to: now))
        #expect(throws: WasteRiskInputError.self) {
            try WasteRiskFeatureBuilder.build(item: value, history: [], on: past, calendar: calendar)
        }
    }

    @Test func riskOnlyBreaksSameDayTiesAndKeepsExpiredSeparate() {
        let early = item(days: 0), low = item(days: 1), high = item(days: 1), later = item(days: 2), expired = item(days: -1)
        var unknown = item(); unknown.expiryDate = nil
        let result = ExpiryPrioritizer.group([later, low, high, early, expired, unknown], on: now,
            calendar: calendar, risk: [early.id: .low, low.id: .low, high.id: .high, later.id: .high])
        #expect(result.upcoming.map(\.id) == [early.id, high.id, low.id, later.id])
        #expect(result.expired.map(\.id) == [expired.id])
        #expect(result.unknown.map(\.id) == [unknown.id])
    }

    @Test func realBundledModelSchemaAndRepeatedInference() async throws {
        let url = try #require(Bundle.main.url(forResource: "WasteRiskClassifier", withExtension: "mlmodelc"))
        let model = try MLModel(contentsOf: url)
        #expect(model.modelDescription.inputDescriptionsByName.count == 7)
        #expect(Set(model.modelDescription.classLabels as? [String] ?? []) == ["Low", "Medium", "High"])
        let service = WasteRiskService(modelURL: url)
        let first = try await service.predict(features(item()))
        let second = try await service.predict(features(item()))
        #expect(first == second)
        // Actual inference, not an assertion of accuracy on an invented label.
        print("WasteRisk real inference: Vegetables, Fridge, 3 days, 1.13 kg, cold start -> \(first.rawValue)")
    }

    @Test func realInferenceCoversAllClassesAcrossExpiryScenarios() async throws {
        let service = WasteRiskService()
        var labels = Set<WasteRiskLevel>()
        for days in [0, 1, 3, 7, 11, 21, 60, 120] {
            let level = try await service.predict(features(item(days: days)))
            labels.insert(level)
            print("Real model, Vegetables/Fridge/1.13kg, days=\(days): \(level.rawValue)")
        }
        #expect(labels == Set(WasteRiskLevel.allCases))
    }

    @Test func quantitiesKeepUnitsAndExtensiveWasteHistoryIsBounded() async throws {
        let history = (0..<40).map { index in event(.wasted, date: now.addingTimeInterval(Double(-index))) }
        let service = WasteRiskService()
        for unit in [QuantityUnit.pieces, .packs, .grams, .kilograms, .millilitres, .litres] {
            var value = item(); value.quantityUnit = unit
            let input = try features(value, history)
            #expect(input.quantityUnit == unit.rawValue && input.quantityValue == value.quantity)
            #expect(input.historyEventCount == 30 && input.historicalWasteRate == 1)
            _ = try await service.predict(input)
        }
        var wasted = item(); wasted.status = .wasted
        #expect(throws: WasteRiskInputError.self) { try features(wasted) }
    }

    @Test func missingAndWrongModelsFailExplicitly() async throws {
        let input = try features(item())
        await #expect(throws: WasteRiskError.self) { _ = try await WasteRiskService(modelURL: nil).predict(input) }
        let wrong = try #require(Bundle.main.url(forResource: "FoodRecognition", withExtension: "mlmodelc"))
        await #expect(throws: WasteRiskError.self) { _ = try await WasteRiskService(modelURL: wrong).predict(input) }
    }

    @Test func predictionFailureIsUnavailableNotAnExpiryRiskLabel() async {
        let result = await WasteRiskAssessment.evaluate(item: item(), history: [], on: now,
            calendar: calendar, service: FailingWasteRisk())
        #expect(result.level == nil && result.unavailableReason != nil)
    }

    @Test func repositoryEditsUsageAndDeletionRefreshRisk() async throws {
        let storage = PersistenceController(inMemory: true)
        await storage.load()
        let repo = PantryRepository(container: try #require(storage.container))
        var draft = FoodDraft(name: "Beans")
        draft.category = .vegetables
        draft.storageLocation = "Fridge"
        draft.expiryDate = Date().addingTimeInterval(3 * 86400)
        let created = try repo.create(draft)
        let pantry = PantryViewModel(repository: repo, riskService: HistoryWasteRisk())
        let details = pantry.detailsModel(id: created.id)
        try await wait { pantry.wasteRisk[created.id]?.level == .low && details.wasteRisk?.level == .low }
        var historyDraft = FoodDraft(name: "Older beans")
        historyDraft.category = .vegetables
        let historyItem = try repo.create(historyDraft)
        _ = try repo.recordUsage(itemID: historyItem.id, type: .wasted, eventID: UUID(), expectedUpdatedAt: historyItem.updatedAt)
        try await wait { pantry.wasteRisk[created.id]?.level == .high && details.wasteRisk?.level == .high }
        draft.expiryDate = nil
        _ = try repo.update(draft)
        try await wait { details.wasteRisk?.unavailableReason != nil }
        #expect(details.wasteRisk?.level == nil)
        try repo.delete(id: created.id)
        #expect(details.item == nil && pantry.items.isEmpty)
        try await wait { pantry.wasteRisk.isEmpty }
    }

    private func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<200 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(predicate())
    }
}

private actor FailingWasteRisk: WasteRiskPredicting {
    func predict(_ features: WasteRiskFeatures) async throws -> WasteRiskLevel { throw WasteRiskError.invalidPrediction }
}
private actor HistoryWasteRisk: WasteRiskPredicting {
    func predict(_ features: WasteRiskFeatures) async throws -> WasteRiskLevel {
        features.historyEventCount == 0 ? .low : .high
    }
}
