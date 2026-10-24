import Foundation
import Observation

@MainActor
@Observable
final class FoodRecognitionViewModel {
    private(set) var result: FoodRecognitionResult?
    private(set) var isRecognizing = false
    private(set) var errorMessage: String?
    private let service: any FoodRecognizing
    private var task: Task<Void, Never>?
    private var generation = UUID()

    init(service: any FoodRecognizing = FoodRecognitionService()) { self.service = service }

    func recognize(_ data: Data) {
        guard !isRecognizing else { return }
        reset()
        let token = generation
        isRecognizing = true
        task = Task { [weak self, service] in
            do {
                let result = try await service.recognize(data)
                guard let self, !Task.isCancelled, self.generation == token else { return }
                self.result = result
                self.isRecognizing = false
            } catch {
                guard let self, !Task.isCancelled, self.generation == token else { return }
                self.errorMessage = "Recognition could not finish. Try another photo or enter details manually.\n\n" + error.localizedDescription
                self.isRecognizing = false
            }
        }
    }

    func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        isRecognizing = false
    }

    func reset() {
        cancel()
        result = nil
        errorMessage = nil
    }
}
