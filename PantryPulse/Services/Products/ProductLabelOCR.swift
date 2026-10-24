import Foundation
import Vision

nonisolated struct LabelText: Equatable, Sendable {
    let text: String
    let confidence: Float
}
nonisolated struct ProductLabelSuggestions: Equatable, Sendable {
    var name: String?
    var brand: String?
    var quantity: LabelQuantity?
    var category: String?
    var lines: [String]
}

nonisolated enum ProductLabelOCR {
    static func recognize(_ data: Data) throws -> [String] { try analyze(data).lines }
    static func analyze(_ data: Data) throws -> ProductLabelSuggestions {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let supported = try request.supportedRecognitionLanguages()
        let preferred = Locale.preferredLanguages.compactMap { language in supported.first { $0.hasPrefix(String(language.prefix(2))) } }
        request.recognitionLanguages = Array(NSOrderedSet(array: preferred + supported.filter { $0.hasPrefix("en") })) as? [String] ?? []
        if request.recognitionLanguages.isEmpty { request.recognitionLanguages = Array(supported.prefix(1)) }
        try VNImageRequestHandler(data: data).perform([request])
        return suggestions(from: (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first.map { LabelText(text: $0.string, confidence: $0.confidence) }
        })
    }
    static func quantity(in text: String) -> LabelQuantity? {
        let pattern = #"(?i)^(?:(?:net\s*(?:weight|contents?)|weight|volume|contents?)\s*[:\-]?\s*)?(\d{1,5}(?:[.,]\d{1,3})?)\s*(kg|g|ml|l)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text.trimmingCharacters(in: .whitespacesAndNewlines), range: NSRange(location: 0, length: (text.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).length)) else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines) as NSString
        guard let number = Double(value.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: ".")), number > 0 else { return nil }
        let unit = value.substring(with: match.range(at: 2)).lowercased()
        return LabelQuantity(value: number, unit: unit == "l" ? "L" : unit)
    }
    static func suggestions(from observations: [LabelText]) -> ProductLabelSuggestions {
        let lines = observations.filter { $0.confidence >= 0.65 }.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let excluded = ["ingredients", "nutrition", "protein", "fat", "energy", "allergen", "contains", "per 100", "expiry", "production", "manufactur"]
        let usable = lines.filter { line in !excluded.contains(where: { line.lowercased().contains($0) }) }
        let vocabulary: [(String, String)] = [
            ("green beans|beetroot|brinjals|leeks|carrots?|tomatoes|eggplant", "Vegetables"),
            ("milk|yogurt|yoghurt|kiripani|curd|cheese", "Dairy"),
            ("mayonnaise|rice|pasta|flour|sauce", "Grains & Pantry"),
            ("apple|banana|orange", "Fruits"), ("bread|bun|croissant", "Bakery"),
            ("chicken|fish|prawn|beef", "Meat & Seafood"), ("juice|tea|coffee|water", "Beverages")
        ]
        var name: String?
        var category: String?
        for line in usable where line.count <= 80 && quantity(in: line) == nil {
            if let match = vocabulary.first(where: { line.range(of: "\\b(" + $0.0 + ")\\b", options: [.regularExpression, .caseInsensitive]) != nil }) {
                name = line.capitalized; category = match.1; break
            }
        }
        let brand = usable.first(where: { $0.lowercased().hasPrefix("brand:") }).map { String($0.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
        return ProductLabelSuggestions(name: name, brand: brand, quantity: usable.compactMap { quantity(in: $0) }.first, category: category, lines: lines)
    }
}
