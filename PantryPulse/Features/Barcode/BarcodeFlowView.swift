import SwiftUI

struct BarcodeFlowView: View {
    @Environment(\.accountResources) private var resources
    let isSelected: Bool
    let save: (FoodDraft) throws -> PantryItem
    let onSaved: () -> Void
    @State private var capture: BarcodeCapture
    @State private var camera: BarcodeCameraModel
    @State private var lookup: BarcodeLookupModel
    @State private var manualEntry = false
    @State private var showingForm = false
    @State private var showingFallback = false
    @State private var startWithPhoto = false
    @State private var retryID = 0
    @State private var visible = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @FocusState private var barcodeFocused: Bool

    init(isSelected: Bool, service: any ProductLookupService = ProductIdentificationService(),
         save: @escaping (FoodDraft) throws -> PantryItem, onSaved: @escaping () -> Void) {
        self.isSelected = isSelected; self.save = save; self.onSaved = onSaved
        let capture = BarcodeCapture()
        _capture = State(initialValue: capture)
        _camera = State(initialValue: BarcodeCameraModel(driver: capture))
        _lookup = State(initialValue: BarcodeLookupModel(service: service))
    }

    private var cameraActive: Bool {
        visible && isSelected && scenePhase == .active && !manualEntry && !showingForm && !showingFallback && lookup.state == .idle
    }

    var body: some View {
        Group {
            if case .found(let product) = lookup.state {
                ProductFoundView(product: product, lookup: lookup, onContinue: { showingForm = true }, onRescan: {
                    lookup.reset(); manualEntry = false
                })
            } else { scanner }
        }
        .navigationTitle("Scan Product")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Cancel") { camera.stop(); lookup.cancelPending(); dismiss() }
                    .accessibilityIdentifier("barcode.cancel")
            }
        }
        .navigationDestination(isPresented: $showingForm) {
            if case .found(let product) = lookup.state {
                AddFoodView(product: product, photoData: lookup.acceptsImage ? lookup.imageData : nil, resources: resources, save: save) {
                    showingForm = false
                    onSaved()
                }
            }
        }
        .navigationDestination(isPresented: $showingFallback) {
            ProductLabelConfirmationView(scan: lookup.scan, startWithPhoto: startWithPhoto, save: save, onSaved: onSaved)
        }
        .onAppear { visible = true }
        .onDisappear { visible = false; camera.stop(); lookup.cancelPending() }
        .onChange(of: isSelected) { _, selected in if !selected { lookup.cancelPending() } }
        .task(id: "\(cameraActive)-\(retryID)") {
            if cameraActive { await camera.start { lookup.symbology = camera.detectedSymbology; lookup.lookup($0) } }
            else { camera.stop() }
        }
    }

    private var scanner: some View {
        ScrollView {
            VStack(spacing: PPSpacing.xl) {
                if !manualEntry {
                    ZStack {
                        BarcodeCameraPreview(session: capture.session)
                        LinearGradient(colors: [.black.opacity(0.4), .clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                        ViewfinderCorners().stroke(PPColors.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .padding(PPSpacing.xl)
                        VStack {
                            Text(camera.state == .running ? "Auto-detect active" : "Barcode camera")
                                .font(PPTypography.badge).padding(PPSpacing.sm).background(.black.opacity(0.75), in: Capsule())
                            Spacer()
                            cameraStatus
                        }.padding(PPSpacing.lg)
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: PPCornerRadius.hero))
                    .accessibilityElement(children: .contain)
                }
                VStack(spacing: PPSpacing.md) {
                    Text(manualEntry ? "Enter barcode" : "Align barcode inside frame")
                        .font(PPTypography.sectionTitle)
                    Text("Identify food using confirmed products, Open Food Facts or label text. Review the details before saving.")
                        .font(PPTypography.body).multilineTextAlignment(.center)
                    if manualEntry {
                        TextField("Barcode value", text: $lookup.barcode)
                            .keyboardType(.asciiCapable)
                            .textContentType(.none)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .padding(PPSpacing.md)
                            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: PPCornerRadius.small))
                            .focused($barcodeFocused)
                            .accessibilityLabel("Barcode")
                            .accessibilityIdentifier("barcode.input")
                        PrimaryButton(title: "Look Up Product", systemImage: "magnifyingglass", isLoading: lookup.state == .loading) {
                            barcodeFocused = false; lookup.lookup()
                        }.disabled(lookup.state == .loading)
                            .accessibilityIdentifier("barcode.lookup")
                    } else {
                        Button("Enter barcode manually", systemImage: "keyboard") {
                            camera.stop(); manualEntry = true
                        }.buttonStyle(.bordered).controlSize(.large)
                            .accessibilityIdentifier("barcode.manual")
                    }
                    if !lookup.barcode.isEmpty {
                        LabeledContent("Detected barcode", value: lookup.barcode)
                        Text("Format: \(lookup.symbology.isEmpty ? "Manual entry" : lookup.symbology)").font(PPTypography.caption)
                    }
                    if lookup.state == .loading {
                        ProgressView("Looking up product…").tint(.white)
                        Button("Cancel Lookup") { lookup.reset() }
                    }
                    if let message = lookup.failureMessage {
                        Text(message).font(PPTypography.body).accessibilityIdentifier("barcode.error")
                        Button("Retry Lookup") { lookup.lookup() }
                        Button("Change Barcode") { lookup.reset(); manualEntry = true }
                        Button("Scan Product Label") { startWithPhoto = true; showingFallback = true }
                        Button("Enter Details Manually") { startWithPhoto = false; showingFallback = true }
                    }
                    if manualEntry {
                        Button("Use Camera", systemImage: "barcode.viewfinder") {
                            barcodeFocused = false; lookup.reset(); manualEntry = false
                        }
                    }
                }
                .padding(PPSpacing.xl)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: PPCornerRadius.hero))
            }
            .padding(PPSpacing.lg)
            .frame(maxWidth: PPMetrics.screenContentWidth)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(.white)
        .tint(PPColors.primary)
        .background(PPColors.tabBarBackground)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer(); Button("Done") { barcodeFocused = false }
            }
        }
    }

    @ViewBuilder private var cameraStatus: some View {
        VStack(spacing: PPSpacing.sm) {
            switch camera.state {
            case .running:
                Text("EAN · UPC · Code 128 · ITF-14").font(PPTypography.caption)
                Button(camera.torchEnabled ? "Turn Light Off" : "Turn Light On", systemImage: "bolt.fill") { camera.toggleTorch() }
            case .starting: ProgressView("Starting camera…").tint(.white)
            case .denied:
                Text("Camera access is disabled. Enter a barcode manually or allow access in Settings.")
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            case .unavailable: Text("Camera unavailable. Enter a barcode manually.")
            case .failed(let message):
                Text(message)
                Button("Retry Camera") { retryID += 1 }
            case .idle, .paused: Text("Camera paused")
            }
        }
        .font(PPTypography.body)
        .multilineTextAlignment(.center)
        .padding(PPSpacing.md)
        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: PPCornerRadius.small))
    }
}

private struct ViewfinderCorners: Shape {
    func path(in rect: CGRect) -> Path {
        let length = min(rect.width, rect.height) * 0.12
        var path = Path()
        for (x, y, dx, dy) in [(rect.minX, rect.minY, 1.0, 1.0), (rect.maxX, rect.minY, -1.0, 1.0),
                               (rect.minX, rect.maxY, 1.0, -1.0), (rect.maxX, rect.maxY, -1.0, -1.0)] {
            path.move(to: CGPoint(x: x, y: y + dy * length))
            path.addLine(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x + dx * length, y: y))
        }
        return path
    }
}
