import SwiftUI
import PhotosUI
import AVFoundation

/// Capture and library selection share the real classifier and existing save form.
struct FoodRecognitionView: View {
    @Environment(\.accountResources) private var resources
    let isSelected: Bool
    let save: (FoodDraft) throws -> PantryItem
    let onSaved: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var model: FoodRecognitionViewModel
    @State private var photoData: Data?
    @State private var selection: PhotosPickerItem?
    @State private var pendingCameraPhoto: Data?
    @State private var cameraCancelled = false
    @State private var camera = false
    @State private var library = false
    @State private var libraryAfterCamera = false
    @State private var started = false
    @State private var retaking = false
    @State private var preparing = false
    @State private var preparationID = UUID()
    @State private var message: String?
    @State private var denied = false
    @State private var confirmation: RecognitionConfirmation?

    init(isSelected: Bool, service: any FoodRecognizing = FoodRecognitionService(),
         save: @escaping (FoodDraft) throws -> PantryItem, onSaved: @escaping () -> Void) {
        self.isSelected = isSelected; self.save = save; self.onSaved = onSaved
        _model = State(initialValue: FoodRecognitionViewModel(service: service))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: PPSpacing.lg) {
                if !started {
                    LoadingStateView(message: "Opening camera…")
                } else if preparing || model.isRecognizing {
                    LoadingStateView(message: preparing ? "Preparing your photo…" : "Recognizing food on this device…")
                    Button("Cancel recognition") { model.cancel(); preparationID = UUID(); preparing = false }
                } else {
                    Image(systemName: "camera.viewfinder").font(.largeTitle).foregroundStyle(PPColors.actionText)
                    Text(message ?? "Capture or choose a food photo").font(PPTypography.sectionTitle)
                    if let error = model.errorMessage {
                        Text(error).foregroundStyle(PPColors.dangerText).accessibilityIdentifier("recognition.error")
                    }
                    if denied { Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } } }
                    PrimaryButton(title: "Take Photo", systemImage: "camera") { Task { await openCamera() } }
                    SecondaryButton(title: "Choose from Photo Library", systemImage: "photo.on.rectangle") { selection = nil; library = true }
                        .accessibilityIdentifier("recognition.library")
                    SecondaryButton(title: "Enter Manually", systemImage: "square.and.pencil") {
                        confirmation = .init(name: "", category: .other, photoData: photoData, notice: "Enter the food details you know.")
                    }.accessibilityIdentifier("recognition.manual")
                    Text("Recognition can be wrong, including for foods outside the model’s classes. Review the name and details before saving.")
                        .font(PPTypography.caption).foregroundStyle(PPColors.secondaryText)
                }
            }.multilineTextAlignment(.center).padding(PPSpacing.lg)
        }
        .background(PPColors.background)
        .navigationTitle("Recognize Food").navigationBarTitleDisplayMode(.inline)
        .task(id: isSelected) {
            guard isSelected, !started else { return }
            await openCamera()
            started = true
        }
        .photosPicker(isPresented: $library, selection: $selection, matching: .images)
        .task(id: selection) {
            guard let selection else { return }
            let token = UUID(); preparationID = token
            preparing = true
            defer { if preparationID == token { preparing = false } }
            do {
                guard let data = try await selection.loadTransferable(type: Data.self) else { throw FoodPhotoError.invalidImage }
                let prepared = try await Task.detached { try FoodPhotoStorage.prepare(data) }.value
                try Task.checkCancellation()
                guard preparationID == token, isSelected else { return }
                self.selection = nil
                photoData = prepared; model.recognize(prepared)
            } catch is CancellationError { }
            catch { message = "This photo could not be loaded. Please choose another." }
        }
        .fullScreenCover(isPresented: $camera, onDismiss: {
            if let data = pendingCameraPhoto {
                pendingCameraPhoto = nil
                prepareCapturedPhoto(data)
            } else if libraryAfterCamera {
                libraryAfterCamera = false; selection = nil; library = true
            } else if cameraCancelled {
                cameraCancelled = false
                // Stay on the actionable recognition screen; allow library/manual entry or retry.
                message = "Capture cancelled. Take another photo or choose one from your library."
            }
        }) {
            FoodCameraPicker(onLibrary: { libraryAfterCamera = true; camera = false }) { image in
                if let image {
                    if let data = image.jpegData(compressionQuality: 0.9) { pendingCameraPhoto = data }
                    else { message = "This photo could not be read. Please try again." }
                } else { cameraCancelled = true }
                camera = false
            }.ignoresSafeArea()
        }
        .onChange(of: model.result?.predictions) { _, _ in
            guard let result = model.result, let best = result.predictions.first else { return }
            let notice = result.needsExtraReview
                ? "Uncertain result — please correct the food name. Model score: \(best.confidence.formatted(.percent.precision(.fractionLength(1))))."
                : "Review this suggestion. Model score: \(best.confidence.formatted(.percent.precision(.fractionLength(1)))). Confidence is not a guarantee of accuracy."
            confirmation = .init(name: best.displayName, category: FoodRecognitionCategory.category(for: best.label), photoData: photoData, notice: notice)
        }
        .onChange(of: isSelected) { _, selected in if !selected { model.cancel(); preparationID = UUID(); preparing = false; camera = false; selection = nil } }
        .onChange(of: scenePhase) { _, phase in if phase == .background { model.cancel(); preparationID = UUID(); preparing = false; camera = false } }
        .onDisappear { model.cancel() }
        .onAppear {
            if retaking { retaking = false; Task { await openCamera() } }
        }
        .navigationDestination(item: $confirmation) { input in
            AddFoodView(recognizedName: input.name, category: input.category, photoData: input.photoData,
                        recognitionNotice: input.notice, onRetake: {
                retaking = true; model.reset(); confirmation = nil
            }, resources: resources, save: save, onSaved: onSaved)
        }
    }

    private func prepareCapturedPhoto(_ data: Data) {
        guard isSelected else { return }
        let token = UUID(); preparationID = token
        preparing = true
        Task {
            defer { if preparationID == token { preparing = false } }
            do {
                let prepared = try await Task.detached { try FoodPhotoStorage.prepare(data) }.value
                guard isSelected, preparationID == token else { return }
                photoData = prepared
                model.recognize(prepared)
            } catch {
                guard preparationID == token else { return }
                message = "This photo could not be read. Please try again."
            }
        }
    }

    private func openCamera() async {
        guard isSelected, !camera, !preparing, !model.isRecognizing else { return }
        denied = false
        message = nil
        #if targetEnvironment(simulator)
        // Some Simulator runtimes advertise a camera but present only a black preview.
        let available = false
        #else
        let available = UIImagePickerController.isSourceTypeAvailable(.camera)
        #endif
        let decision = FoodCameraAccess.decision(available: available,
                                                 status: AVCaptureDevice.authorizationStatus(for: .video))
        switch decision {
        case .available: camera = true
        case .requestPermission:
            if await AVCaptureDevice.requestAccess(for: .video) { if isSelected, !Task.isCancelled { camera = true } }
            else { denied = true; message = "Camera access is off. Choose a photo or enable access in Settings." }
        case .denied: denied = true; message = "Camera access is off. Choose a photo or enable access in Settings."
        case .unavailable: message = "Camera unavailable. Choose a food photo from your library."
        }
    }
}

private struct RecognitionConfirmation: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let category: FoodCategory
    let photoData: Data?
    let notice: String
}
