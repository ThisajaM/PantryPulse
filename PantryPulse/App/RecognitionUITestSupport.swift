#if DEBUG
import Foundation

/// Explicit UI-test injection only; excluded from Release and normal Debug launches.
enum RecognitionUITestSupport {
    static var configuredService: (any FoodRecognizing)? {
        let environment = ProcessInfo.processInfo.environment
        guard let suite = environment["PANTRYPULSE_UI_TEST_DEFAULTS"],
              suite.hasPrefix("PantryPulse.UITests."),
              UUID(uuidString: String(suite.dropFirst("PantryPulse.UITests.".count))) != nil,
              let scenario = environment["PANTRYPULSE_RECOGNITION_TEST"],
              ["success", "ambiguous", "failure"].contains(scenario) else { return nil }
        return MockRecognizer(scenario: scenario)
    }

    private actor MockRecognizer: FoodRecognizing {
        let scenario: String
        init(scenario: String) { self.scenario = scenario }
        func recognize(_ imageData: Data) async throws -> FoodRecognitionResult {
            try await Task.sleep(for: .milliseconds(300))
            if scenario == "failure" { throw FoodRecognitionError.noResults }
            return FoodRecognitionResult(predictions: [
                FoodPrediction(label: "Apple", confidence: scenario == "ambiguous" ? 0.40 : 0.92),
                FoodPrediction(label: "Pear", confidence: scenario == "ambiguous" ? 0.38 : 0.05)
            ], supportedLabels: ["Apple", "Pear"])
        }
    }
}
#endif
