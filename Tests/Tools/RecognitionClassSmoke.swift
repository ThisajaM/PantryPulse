// Run with: swift RecognitionClassSmoke.swift MODEL TESTING_DIRECTORY OUTPUT_JSON
// Real-model coverage smoke check; never used by the app or as a dataset accuracy claim.
import Foundation
import CoreML
import Vision
import ImageIO
import AppKit
import CoreImage

struct Row: Codable {
    let fixture: String
    let expected: String?
    let predicted: String
    let confidence: Float
    let candidateCount: Int
}
let args = CommandLine.arguments
precondition(args.count == 4, "Provide model, labelled testing directory, and output JSON")
let compiled = try MLModel.compileModel(at: URL(fileURLWithPath: args[1]))
let model = try MLModel(contentsOf: compiled)
let vision = try VNCoreMLModel(for: model)
let labels = model.modelDescription.classLabels as! [String]
let root = URL(fileURLWithPath: args[2])
var rows: [Row] = []
func classify(_ data: Data, fixture: String, expected: String?) throws {
    let source = CGImageSourceCreateWithData(data as CFData, nil)!
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let orientation = CGImagePropertyOrientation(rawValue: (properties?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1) ?? .up
    let request = VNCoreMLRequest(model: vision)
    request.imageCropAndScaleOption = .centerCrop
    try VNImageRequestHandler(data: data, orientation: orientation).perform([request])
    let results = request.results as! [VNClassificationObservation]
    precondition(results.count == labels.count && results.allSatisfy { $0.confidence.isFinite })
    let first = results[0]
    rows.append(Row(fixture: fixture, expected: expected, predicted: first.identifier,
                    confidence: first.confidence, candidateCount: results.count))
}
var firstPhoto: Data?
for label in labels.sorted() {
    let directory = root.appendingPathComponent(label)
    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { ["jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    guard let file = files.first else { fatalError("No test photo for \(label)") }
    let data = try Data(contentsOf: file)
    if label == "Banana" { firstPhoto = data }
    try classify(data, fixture: label + "/" + file.lastPathComponent, expected: label)
}
// An unsupported geometric non-food drawing, not a food sample or an OOD detector benchmark.
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 320, pixelsHigh: 320,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor.white.setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: 320, height: 320)).fill()
NSColor.blue.setFill(); NSBezierPath(rect: NSRect(x: 70, y: 70, width: 180, height: 180)).fill()
NSGraphicsContext.restoreGraphicsState()
try classify(bitmap.representation(using: .png, properties: [:])!, fixture: "unsupported-blue-square", expected: nil)
let banana = firstPhoto!
let source = CGImageSourceCreateWithData(banana as CFData, nil)!
let cg = CGImageSourceCreateImageAtIndex(source, 0, nil)!
let rotated = NSMutableData()
let destination = CGImageDestinationCreateWithData(rotated, "public.jpeg" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, cg, [kCGImagePropertyOrientation: 6] as CFDictionary)
CGImageDestinationFinalize(destination)
try classify(rotated as Data, fixture: "Banana-EXIF-orientation-6", expected: "Banana")
let orientedResult = rows.last!
let rotatedSource = CGImageSourceCreateWithData(rotated as CFData, nil)!
let normalized = CGImageSourceCreateThumbnailAtIndex(rotatedSource, 0, [
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceCreateThumbnailWithTransform: true,
    kCGImageSourceThumbnailMaxPixelSize: max(cg.width, cg.height)
] as CFDictionary)!
let normalizedData = NSBitmapImageRep(cgImage: normalized).representation(using: .png, properties: [:])!
try classify(normalizedData, fixture: "Banana-normalized-rotation", expected: "Banana")
precondition(rows.last!.predicted == orientedResult.predicted && abs(rows.last!.confidence - orientedResult.confidence) < 0.01,
             "EXIF-oriented and normalized pixels must produce equivalent predictions")
let blurred = CIImage(cgImage: cg).applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 80])
let context = CIContext()
let blurImage = context.createCGImage(blurred, from: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))!
let blurData = NSBitmapImageRep(cgImage: blurImage).representation(using: .png, properties: [:])!
try classify(blurData, fixture: "Banana-heavy-blur", expected: "Banana")
let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(rows).write(to: URL(fileURLWithPath: args[3]))
print("Completed \(labels.count) class samples and 4 challenge inputs; \(rows.count) real inference calls. See JSON for predictions, not a dataset accuracy estimate.")
