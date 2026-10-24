import Foundation
import CoreML
import Vision
import ImageIO

nonisolated protocol FoodRecognizing: Sendable {
    func recognize(_ imageData: Data) async throws -> FoodRecognitionResult
}

nonisolated enum FoodRecognitionError: LocalizedError {
    case modelMissing, invalidModel, invalidImage, noResults
    var errorDescription: String? {
        switch self {
        case .modelMissing: "The food recognition model is unavailable. You can still enter food manually."
        case .invalidModel: "The food recognition model has an unsupported format. Please enter food manually."
        case .invalidImage: "This photo could not be read. Choose another image or take a new photo."
        case .noResults: "No usable food suggestions were returned. Try another photo or enter food manually."
        }
    }
}

/// Serial actor owns model loading and inference, away from the UI actor.
actor FoodRecognitionService: FoodRecognizing {
    private let modelURL: URL?
    private var model: VNCoreMLModel?
    private var labels: [String] = []

    init(modelURL: URL? = Bundle.main.url(forResource: "FoodRecognition", withExtension: "mlmodelc")) {
        self.modelURL = modelURL
    }

    func recognize(_ imageData: Data) async throws -> FoodRecognitionResult {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { throw FoodRecognitionError.invalidImage }
        if model == nil {
            guard let modelURL else { throw FoodRecognitionError.modelMissing }
            let configuration = MLModelConfiguration()
            #if targetEnvironment(simulator)
            // Simulator has no device Neural Engine; use the supported CPU backend.
            configuration.computeUnits = .cpuOnly
            #else
            configuration.computeUnits = .all
            #endif
            let loaded = try MLModel(contentsOf: modelURL, configuration: configuration)
            let description = loaded.modelDescription
            guard let input = description.inputDescriptionsByName["image"]?.imageConstraint,
                  input.pixelsWide == 299, input.pixelsHigh == 299,
                  description.predictedFeatureName == "target",
                  description.predictedProbabilitiesName == "targetProbability",
                  let classes = description.classLabels as? [String], !classes.isEmpty else {
                throw FoodRecognitionError.invalidModel
            }
            labels = classes
            model = try VNCoreMLModel(for: loaded)
        }
        guard let model else { throw FoodRecognitionError.invalidModel }
        let request = VNCoreMLRequest(model: model)
        // Whole-photo classification: center the food; no object boxes or quantity estimation.
        request.imageCropAndScaleOption = .centerCrop
        #if targetEnvironment(simulator)
        for (stage, devices) in try request.supportedComputeStageDevices {
            if let cpu = devices.first(where: { if case .cpu = $0 { return true }; return false }) {
                request.setComputeDevice(cpu, for: stage)
            }
        }
        #endif
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let rawOrientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: rawOrientation) ?? .up
        let handler = VNImageRequestHandler(data: imageData, orientation: orientation)
        try Task.checkCancellation()
        try handler.perform([request])
        try Task.checkCancellation()
        let known = Set(labels)
        let predictions = (request.results as? [VNClassificationObservation] ?? [])
            .filter { known.contains($0.identifier) && $0.confidence.isFinite && (0...1).contains($0.confidence) }
            .map { FoodPrediction(label: $0.identifier, confidence: Double($0.confidence)) }
            .sorted { $0.confidence > $1.confidence }
        guard !predictions.isEmpty else { throw FoodRecognitionError.noResults }
        return FoodRecognitionResult(predictions: predictions, supportedLabels: labels)
    }
}
