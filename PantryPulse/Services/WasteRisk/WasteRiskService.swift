import Foundation
import CoreML

nonisolated enum WasteRiskLevel: String, CaseIterable, Sendable {
    case low = "Low", medium = "Medium", high = "High"
    var priority: Int { switch self { case .low: 0; case .medium: 1; case .high: 2 } }
}

nonisolated protocol WasteRiskPredicting: Sendable {
    func predict(_ features: WasteRiskFeatures) async throws -> WasteRiskLevel
}

nonisolated enum WasteRiskError: LocalizedError {
    case modelMissing, invalidSchema, invalidPrediction
    var errorDescription: String? {
        switch self {
        case .modelMissing: "The waste-risk model is unavailable. Expiry-based priority remains available."
        case .invalidSchema: "The waste-risk model has an incompatible schema. Expiry-based priority remains available."
        case .invalidPrediction: "The model returned an unsupported result. Expiry-based priority remains available."
        }
    }
}

/// One reusable model owned by a serial actor. No Vision adapter is needed for tabular inputs.
actor WasteRiskService: WasteRiskPredicting {
    private let modelURL: URL?
    private var model: MLModel?

    init(modelURL: URL? = Bundle.main.url(forResource: "WasteRiskClassifier", withExtension: "mlmodelc")) {
        self.modelURL = modelURL
    }

    func predict(_ features: WasteRiskFeatures) async throws -> WasteRiskLevel {
        try Task.checkCancellation()
        if model == nil {
            guard let modelURL else { throw WasteRiskError.modelMissing }
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .cpuOnly
            let loaded = try MLModel(contentsOf: modelURL, configuration: configuration)
            let expected: [String: MLFeatureType] = ["category": .string, "storageType": .string,
                "daysUntilExpiry": .int64, "quantityValue": .double, "quantityUnit": .string,
                "historyEventCount": .int64, "historicalWasteRate": .double]
            let description = loaded.modelDescription
            guard description.inputDescriptionsByName.count == expected.count,
                  expected.allSatisfy({ description.inputDescriptionsByName[$0.key]?.type == $0.value }),
                  description.predictedFeatureName == "riskLabel",
                  description.outputDescriptionsByName["riskLabel"]?.type == .string,
                  Set(description.classLabels as? [String] ?? []) == Set(WasteRiskLevel.allCases.map(\.rawValue)) else {
                throw WasteRiskError.invalidSchema
            }
            model = loaded
        }
        guard let model else { throw WasteRiskError.modelMissing }
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "category": MLFeatureValue(string: features.category),
            "storageType": MLFeatureValue(string: features.storageType),
            "daysUntilExpiry": MLFeatureValue(int64: Int64(features.daysUntilExpiry)),
            "quantityValue": MLFeatureValue(double: features.quantityValue),
            "quantityUnit": MLFeatureValue(string: features.quantityUnit),
            "historyEventCount": MLFeatureValue(int64: Int64(features.historyEventCount)),
            "historicalWasteRate": MLFeatureValue(double: features.historicalWasteRate)
        ])
        let output = try await model.prediction(from: input)
        try Task.checkCancellation()
        guard let value = output.featureValue(for: "riskLabel")?.stringValue,
              let level = WasteRiskLevel(rawValue: value) else { throw WasteRiskError.invalidPrediction }
        // The probability dictionary is deliberately not presented as calibrated waste probability.
        return level
    }
}

struct WasteRiskAssessment: Equatable {
    let level: WasteRiskLevel?
    let explanation: [String]
    let unavailableReason: String?

    static func evaluate(item: PantryItem, history: [UsageEvent], on date: Date,
                         calendar: Calendar, service: any WasteRiskPredicting) async -> Self {
        do {
            let features = try WasteRiskFeatureBuilder.build(item: item, history: history, on: date, calendar: calendar)
            let level = try await service.predict(features)
            return Self(level: level, explanation: features.explanations, unavailableReason: nil)
        } catch {
            return Self(level: nil, explanation: [], unavailableReason: error.localizedDescription)
        }
    }
}
