import SwiftUI
import Observation

@MainActor
@Observable
final class FoodPhotoLoader {
    private(set) var image: UIImage?
    func load(_ path: String?, photos: FoodPhotoStorage = FoodPhotoStorage()) async {
        image = nil
        guard let path else { return }
        do {
            let data = try await Task.detached { try photos.load(path) }.value
            try Task.checkCancellation()
            image = UIImage(data: data)
        } catch {
            // A missing/corrupt photo intentionally renders the explicit unavailable placeholder.
            if !Task.isCancelled { image = nil }
        }
    }
}

/// Only local, app-owned image paths are supported. No sample photo replaces missing data.
struct StoredFoodImageView: View {
    @Environment(\.accountResources) private var resources
    let path: String?
    @State private var photo = FoodPhotoLoader()

    var body: some View {
        Group {
            if let image = photo.image {
                Image(uiImage: image).resizable().scaledToFit()
                    .accessibilityLabel("Food photo")
            } else {
                Label(path == nil ? "No photo added" : "Photo unavailable", systemImage: "photo")
                    .font(PPTypography.body).foregroundStyle(PPColors.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(PPSpacing.xl)
                    .background(PPColors.mutedSurface)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: PPCornerRadius.card))
        .task(id: path) { await photo.load(path, photos: resources.photos) }
    }
}
