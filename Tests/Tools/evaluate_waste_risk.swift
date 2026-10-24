import Foundation
import CoreML
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let url = try MLModel.compileModel(at: root.appendingPathComponent("PantryPulse/Models/WasteRiskClassifier.mlmodel"))
let model = try MLModel(contentsOf: url)
for split in ["train", "validation", "test"] {
    let csv = try String(contentsOf: root.appendingPathComponent("ml-training/waste-risk/datasets/\(split).csv"), encoding: .utf8)
    let lines = csv.components(separatedBy: .newlines).filter { !$0.isEmpty }
    var correct = 0
    var baselineCorrect = 0
    var matrix: [String: Int] = [:]
    for line in lines.dropFirst() {
        let v = line.components(separatedBy: ",")
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "category": v[0], "storageType": v[1], "daysUntilExpiry": Int64(v[2])!,
            "quantityValue": Double(v[3])!, "quantityUnit": v[4],
            "historyEventCount": Int64(v[5])!, "historicalWasteRate": Double(v[6])!
        ])
        let prediction = try model.prediction(from: input).featureValue(for: "riskLabel")!.stringValue
        // Predeclared expiry-only comparator: urgent=High, soon=Medium, fresh=Low.
        let days = Int(v[2])!
        let baseline = days <= 1 ? "High" : days <= 3 ? "Medium" : "Low"
        if baseline == v[7] { baselineCorrect += 1 }
        if prediction == v[7] { correct += 1 }
        matrix["\(v[7])->\(prediction)", default: 0] += 1
    }
    print("\(split): \(correct)/\(lines.count - 1), \(Double(correct) / Double(lines.count - 1) * 100)% synthetic-label agreement")
    print("Expiry baseline: \(baselineCorrect)/\(lines.count - 1), \(Double(baselineCorrect) / Double(lines.count - 1) * 100)%")
    print(matrix.sorted { $0.key < $1.key })
}
