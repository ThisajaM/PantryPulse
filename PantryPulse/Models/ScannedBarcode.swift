import Foundation

nonisolated struct ScannedBarcode: Equatable, Sendable {
    let rawValue: String
    let symbology: String

    var format: String { symbology.replacingOccurrences(of: "VNBarcodeSymbology", with: "").lowercased() }

    /// Only known GTIN carriers (or conventional manual EAN/UPC input) require a checksum.
    /// Code 128 text is opaque, even if it happens to contain 13 or 14 digits.
    func identity() throws -> BarcodeIdentity {
        guard !rawValue.isEmpty, rawValue.utf8.count <= 256,
              !rawValue.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ProductLookupError.invalidBarcode
        }
        let value: String
        switch format {
        case "upce": value = try GTIN.expandUPCE(rawValue)
        case "ean13", "ean8", "upca", "itf14":
            let length = ["ean13": 13, "ean8": 8, "upca": 12, "itf14": 14][format]
            guard rawValue.count == length else { throw ProductLookupError.invalidBarcode }
            value = rawValue
        case "", "manual":
            if [8, 12, 13].contains(rawValue.count) { value = rawValue }
            else if rawValue.count == 14 && GTIN.isValid(rawValue) { value = rawValue }
            else { return BarcodeIdentity(key: "opaque:" + rawValue, globalCode: nil) }
        default: return BarcodeIdentity(key: "opaque:" + rawValue, globalCode: nil)
        }
        guard GTIN.isValid(value) else { throw ProductLookupError.invalidBarcode }
        return BarcodeIdentity(key: "gtin:" + String(repeating: "0", count: 14 - value.count) + value, globalCode: value)
    }
}

nonisolated struct BarcodeIdentity: Equatable, Sendable {
    let key: String
    let globalCode: String?
}

nonisolated enum GTIN {
    static func isValid(_ value: String) -> Bool {
        let digits = Array(value.utf8)
        guard [8, 12, 13, 14].contains(digits.count), digits.allSatisfy({ (48...57).contains($0) }) else { return false }
        let sum = digits.dropLast().reversed().enumerated().reduce(0) { $0 + Int($1.element - 48) * ($1.offset.isMultiple(of: 2) ? 3 : 1) }
        return (10 - sum % 10) % 10 == Int(digits.last! - 48)
    }
    static func expandUPCE(_ value: String) throws -> String {
        let d = Array(value)
        guard value.utf8.allSatisfy({ (48...57).contains($0) }), d.count == 8, d[0] == "0" || d[0] == "1" else {
            throw ProductLookupError.invalidBarcode
        }
        let body: String
        switch d[6] {
        case "0", "1", "2": body = String([d[0], d[1], d[2], d[6]]) + "0000" + String(d[3...5])
        case "3": body = String(d[0...3]) + "00000" + String(d[4...5])
        case "4": body = String(d[0...4]) + "00000" + String(d[5])
        default: body = String(d[0...5]) + "0000" + String(d[6])
        }
        let expanded = body + String(d[7])
        guard isValid(expanded) else { throw ProductLookupError.invalidBarcode }
        return expanded
    }
}
