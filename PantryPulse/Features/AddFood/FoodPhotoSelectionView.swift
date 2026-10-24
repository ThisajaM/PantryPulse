import SwiftUI
import PhotosUI
import AVFoundation

@MainActor
@Observable
final class FoodPhotoSelectionState {
    var showingChoices = false
    var showingCamera = false
    var selection: PhotosPickerItem?
    var photoError: String?
    var offerSettings = false
}

struct FoodPhotoSelectionView: View {
    @Bindable var model: AddFoodViewModel
    @Bindable var state: FoodPhotoSelectionState
    init(model: AddFoodViewModel) {
        self.model = model
        self.state = model.photoSelection
    }
    @Environment(\.openURL) private var openURL

    private var hasPhoto: Bool { model.photoData != nil || (!model.removedPhoto && model.draft.imagePath != nil) }

    var body: some View {
        VStack(spacing: PPSpacing.sm) {
            Button { state.selection = nil; state.photoError = nil; state.offerSettings = false; state.showingChoices = true } label: {
                VStack(spacing: PPSpacing.sm) {
                    if let data = model.photoData, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 180)
                            .clipShape(RoundedRectangle(cornerRadius: PPCornerRadius.image))
                    } else if !model.removedPhoto, let path = model.draft.imagePath {
                        StoredFoodImageView(path: path).frame(maxHeight: 180)
                    } else {
                        HStack(spacing: PPSpacing.md) {
                            Image(systemName: "camera.badge.ellipsis")
                                .font(.title2)
                                .foregroundStyle(PPColors.primary)
                                .frame(width: 64, height: 64)
                                .accessibilityHidden(true)
                            .background(PPColors.mutedSurface.opacity(0.7), in: RoundedRectangle(cornerRadius: PPCornerRadius.image))
                            VStack(alignment: .leading, spacing: PPSpacing.xs) {
                                Text("Item Visual").font(PPTypography.cardTitle).foregroundStyle(PPColors.text)
                                Text("Optional · Add a photo to help you find this food in your pantry.")
                                    .font(PPTypography.caption).foregroundStyle(PPColors.secondaryText)
                            }
                        }
                    }
                    if hasPhoto { Text("Replace Food Photo").font(PPTypography.cardTitle) }
                }
                .frame(maxWidth: .infinity, minHeight: PPMetrics.minimumTapTarget)
                .foregroundStyle(PPColors.actionText)
                .padding(PPSpacing.md)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("addFood.photo")
            .accessibilityLabel(hasPhoto ? "Replace Food Photo" : "Add Food Photo")
            .disabled(model.isLoadingPhoto)
            if model.isLoadingPhoto { ProgressView("Loading photo…") }
            if let photoError = state.photoError {
                Text(photoError).font(PPTypography.caption).foregroundStyle(PPColors.dangerText)
                    .accessibilityIdentifier("addFood.photoError")
                if state.offerSettings {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            }
            if hasPhoto {
                Button("Remove Photo", role: .destructive) {
                    state.selection = nil
                    model.removePhoto()
                }.disabled(model.isLoadingPhoto)
            }
        }
        .task(id: model.photoSelection.selection) {
            let state = model.photoSelection
            guard let selected = state.selection else { return }
            state.showingChoices = false
            model.isLoadingPhoto = true
            defer { if state.selection == selected { model.isLoadingPhoto = false } }
            do {
                guard let data = try await selected.loadTransferable(type: Data.self) else { throw FoodPhotoError.invalidImage }
                let prepared = try await Task.detached { try FoodPhotoStorage.prepare(data) }.value
                try Task.checkCancellation()
                guard state.selection == selected else { return }
                model.selectPhoto(prepared)
            } catch is CancellationError { }
            catch { if !Task.isCancelled { state.photoError = error.localizedDescription } }
        }
        .sheet(isPresented: $state.showingChoices) {
            VStack(spacing: PPSpacing.lg) {
                Text("Food Photo").font(PPTypography.sectionTitle)
                Button("Take Photo", systemImage: "camera") { Task { await openCamera() } }
                PhotosPicker(selection: $state.selection, matching: .images) {
                    Label("Choose from Photo Library", systemImage: "photo.on.rectangle")
                }
                if let error = state.photoError {
                    Text(error).font(PPTypography.caption).foregroundStyle(PPColors.dangerText)
                        .accessibilityIdentifier("addFood.photoError")
                    if state.offerSettings {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                }
                Button("Cancel", role: .cancel) { state.showingChoices = false }
                    .accessibilityIdentifier("photoSource.cancel")
            }
            .font(PPTypography.body)
            .tint(PPColors.actionText)
            .padding(PPSpacing.lg)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .fullScreenCover(isPresented: $state.showingCamera) {
                FoodCameraPicker { image in
                    state.showingCamera = false
                    guard let image else { return }
                    state.showingChoices = false
                    model.isLoadingPhoto = true
                    Task {
                        defer { model.isLoadingPhoto = false }
                        do {
                            guard let data = image.jpegData(compressionQuality: 1) else { throw FoodPhotoError.invalidImage }
                            let prepared = try await Task.detached { try FoodPhotoStorage.prepare(data) }.value
                            model.selectPhoto(prepared)
                        } catch { state.photoError = error.localizedDescription }
                    }
                }.ignoresSafeArea()
            }
        }

    }

    private func openCamera() async {
        state.offerSettings = false
        #if targetEnvironment(simulator)
        let cameraAvailable = false
        #else
        let cameraAvailable = UIImagePickerController.isSourceTypeAvailable(.camera)
        #endif
        let decision = FoodCameraAccess.decision(available: cameraAvailable, status: AVCaptureDevice.authorizationStatus(for: .video))
        switch decision {
        case .unavailable: state.photoError = "A camera is not available on this device. You can choose a photo from your library."
        case .denied:
            state.offerSettings = true
            state.photoError = "Camera access is disabled. Allow camera access in Settings to take a food photo, or choose one from your library."
        case .available: state.showingCamera = true
        case .requestPermission:
            let allowed = await AVCaptureDevice.requestAccess(for: .video)
            guard state.showingChoices else { return }
            if allowed { state.showingCamera = true }
            else { state.offerSettings = true; state.photoError = "Camera access was not allowed. You can enable it in Settings or choose a library photo." }
        }
    }
}
