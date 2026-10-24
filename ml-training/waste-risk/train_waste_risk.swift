// macOS Create ML training script. Run using the Swift toolchain supplied with Xcode.
// Labels are synthetic scenario labels, not observed real-world food waste outcomes.
import Foundation
import CreateML

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let csvRoot = root.appendingPathComponent("datasets", isDirectory: true)
let training = try MLDataTable(contentsOf: csvRoot.appendingPathComponent("train.csv"))
let validation = try MLDataTable(contentsOf: csvRoot.appendingPathComponent("validation.csv"))
let testing = try MLDataTable(contentsOf: csvRoot.appendingPathComponent("test.csv"))

print("Training rows: \(training.rows.count)")
print("Validation rows: \(validation.rows.count)")
print("Testing rows: \(testing.rows.count)")
print("Training table summary: \(training)")

let model = try MLClassifier(trainingData: training, targetColumn: "riskLabel")
let heldOutValidationMetrics = model.evaluation(on: validation)
let heldOutTestMetrics = model.evaluation(on: testing)

// These numbers ONLY measure agreement with synthetic labels.
print("Training accuracy on synthetic scenarios: \((1 - model.trainingMetrics.classificationError) * 100)%")
print("Held-out validation accuracy on synthetic scenarios: \((1 - heldOutValidationMetrics.classificationError) * 100)%")
print("Held-out test accuracy on synthetic scenarios: \((1 - heldOutTestMetrics.classificationError) * 100)%")
print("Held-out test confusion summary: \(heldOutTestMetrics.confusion)")

// Export separately; never overwrite the app's verified model implicitly.
let output = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : root.appendingPathComponent("WasteRiskClassifier.mlmodel")
guard !FileManager.default.fileExists(atPath: output.path) else {
    throw NSError(domain: "WasteRiskTraining", code: 1,
                  userInfo: [NSLocalizedDescriptionKey: "Output already exists; choose a new export path."])
}
try model.write(to: output, metadata: nil)
print("Exported: \(output.path)")
