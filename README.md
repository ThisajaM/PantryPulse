# PantryPulse

Native iOS coursework application for food inventory, expiry reminders, and reducing household food waste.

## Day 5 — on-device food recognition

Scan → Recognize Food uses the supplied `FoodRecognition.mlmodel` through Vision and Core ML. Take a photo with the existing native camera or choose one from Photos; recognition runs on-device and automatically opens an editable review of the best prediction with its actual model score. The exported classifier has 151 classes and a 299 × 299 colour-image input. Low-confidence or closely ranked suggestions receive an extra review notice. Unsupported foods can still receive confident incorrect labels, so every result requires confirmation.

Review the best result or enter details manually, then confirm quantity, storage, purchase date and optional expiry in the existing Add Food form. No recognition result is saved automatically, and the model does not estimate quantity, shelf life, freshness or safety. Existing photo persistence and the Core Data repository handle confirmed saves. See [model schema, supported classes, evaluation and verification](docs/FOOD_RECOGNITION.md).

Verification (22 October): Debug/Release builds passed; 93 Simulator unit tests passed with the known Vision inference limitation explicitly checked. Navigation, onboarding and recognition/manual-fallback UI cases passed across regression and focused runs. Nine physical iPhone recognition/photo tests passed, and the user confirmed grapes recognition. Full evidence and limitations are in the linked model report.

Day 5 verification extension: 155 real-model smoke calls covered all 151 class folders plus four challenge inputs; this is coverage, not a new accuracy estimate. A fresh Debug test run passed 93 unit tests and two mock-based UI tests, and Release passed. See the model report for results and Simulator limitations.

## Day 4 — expiry, reminders, consumption/waste and Insights

The shared `ExpiryService` drives all expiry labels and Dashboard counts. Use First now opens a working list of active foods ordered by recorded expiry, with unknown dates separated and a dedicated Expired Items destination. Settings → Expiry Reminders enables local notification permission, configurable reminder time (09:00 by default), and three-day/one-day/expiry-day alerts. Changes to saved inventory reconcile the nearest 60 pending reminders. Expiry labels are not a food-safety assessment; the separate experimental Day 6 risk model is described below. See [implementation, limits and verification](docs/DAY4_EXPIRY_REMINDERS.md).

Food Details now records confirmed full-item consumption or waste. The repository saves the history event and zero remaining quantity/inactive status atomically; history survives item deletion. Insights shows recorded event and distinct-item counts, outcome charts, wasted categories and recent activity with period filters. Quantities retain their individual units; no savings or environmental impact is inferred. Partial usage and history editing remain deferred. See [usage/history implementation and verification](docs/DAY4_USAGE_INSIGHTS.md).

## Day 3 — barcode lookup and confirmation

Scan → Scan a Barcode opens a live AVFoundation preview with Vision barcode detection, or manual entry for Simulator and devices without camera access. EAN-13 (including UPC-A represented with a leading zero), EAN-8, UPC-E, Code 128 and ITF-14 are requested when supported by Vision. Capture and analysis run on a serial background queue; the first detection pauses capture. Leaving the screen, changing tabs, or backgrounding stops the camera.

Confirmed local catalogue lookup and Open Food Facts show actual optional product metadata and a downloadable photo, with explicit loading/error/retry states. Review & Add to Pantry reuses the existing form and repository. Remaining quantity is blank until entered or explicitly accepted from packaging OCR; expiry is optional and never inferred. Users can correct the category, dates and storage, change notes, and accept, replace or remove the photo. Only confirmed saves write inventory and local photos. Product sources and licence links appear in confirmation, imported notes, and About.

No new packages, database schema changes, or food classification were added. See [Day 3 implementation and verification](docs/DAY3_BARCODE.md) and [API service contract](docs/OPEN_FOOD_FACTS.md).

## Day 2 status

The versioned Core Data model now includes `PantryItem` and `UsageEvent`. `PersistenceRootView` loads a production SQLite store and injects its context into the existing launch flow. Loading failures show a retry screen; save failures are thrown to callers. No data is seeded. Tests and previews use isolated stores.

`PantryRepositoryProtocol` and `PantryRepository` provide create, fetch-all/active/by-ID, update, delete, name search, category filtering, and expiry/creation sorting. `FoodDraft` validates and normalizes input; shared enums define persisted categories, units, and statuses. The app injects one repository-backed `PantryViewModel` into Home and Pantry. Saved mutations publish changes and refetch active inventory without resetting filters or navigation. No production inventory is seeded. Add Food now saves through this shared repository. Food Details resolves records by UUID, observes changes, and supports editing plus confirmed deletion.

The native Add Food form is available from Home, Pantry, and Scan → Enter Manually. It collects name, category, quantity/unit, purchase date, optional expiry, storage location, and optional notes. Validation and persistence failures keep the form open; successful saves return to the originating screen. Food photos can be selected with PhotosPicker or captured on a physical iPhone, then saved locally with the food item. See `docs/FOOD_PHOTOS.md` for photo storage and verification, and `docs/DAY2_PHASE_C.md` for the original form design adaptations.

Keep a draft's UUID across save retries: creating the same normalized draft is idempotent, while different contents with an existing UUID report a conflict. Updates preserve identity/creation time and advance `updatedAt`. Main-actor repository calls serialize the check/save sequence; all app writes must go through the shared repository. Direct managed-object writes bypass validation and change publication. There is no schema uniqueness constraint or cross-process writer coordination in this phase.

The repository owns a separate main-queue context and rolls it back on save failure, preserving other contexts' edits. Core Data errors propagate; view-model fetch errors surface in a retry alert. Unknown expiry dates sort last; overdue dates remain valid. Active inventory quantity must be finite and positive (completed consumed/wasted items have zero remaining quantity), and trimmed names/storage locations must be nonempty. Optional blank text becomes nil. `imagePath` supports app-owned local photos in Food Details; missing files show an unavailable state. Add/Edit supports replacing and removing saved photos. Consumption/waste actions now use a dedicated atomic repository operation to record UsageEvent snapshots alongside the inventory update.

The `PantryItem` entity generates `PantryItemRecord`, and `UsageEvent` generates `UsageEventRecord`, avoiding a collision with the existing Swift value type. There are no hand-written managed-object subclasses. Events retain UUID and name/category snapshots without relationships, so future item deletion cannot cascade into history.

The original model version and `Item.timestamp` entity are retained. The new version adds entities and enables inferred lightweight migration; failures never delete or replace the user's store. The current model has no sample defaults or seeded rows. Production uses `PantryPulse.sqlite` in Core Data's default directory; previews use `NSInMemoryStoreType`, while disk tests use unique temporary locations.

Pantry combines case-insensitive name search, shared-category filters (including All Items), and four sort modes: recently added, expiry soonest, name ascending, and name descending. Unknown expiry dates sort last. Edit/Delete update the same saved inventory immediately. Delete requires a native confirmation alert.

See `docs/DAY2_PHASE_D.md` for Details design adaptations and `docs/DAY2_PHASE_E.md` for inventory-management verification.

Home derives totals, expiry counts, recently added items, and the Use First preview from the same saved active inventory as Pantry. Shared calendar-day classification is expired (<0), urgent (0–1), expiring soon (2–3), fresh (4+), or unknown (no date). Expired items remain in the active total until their status changes, but are separate from urgent and excluded from Use First. Use First shows the earliest upcoming dates, including dates beyond three days. Summaries refresh on successful writes, foreground activation, local day changes, and significant clock changes. See `docs/DAY2_PHASE_F.md` for verification.

## Day 1 baseline (historical)

The existing Xcode project is preserved. First launch shows a three-page introduction, then opens a native SwiftUI shell with Home, Pantry, Scan, Insights, and Settings tabs. Home and Pantry share one `PantryViewModel`, created at the composition root. Production inventory starts empty; there is no persistence integration or editing workflow yet. Unfinished capabilities explicitly say “Coming in a later phase”.

Home Dashboard, My Pantry, and Empty Pantry now use the inspected Figma layouts, with native navigation and responsive card grids. At the end of Day 1, production inventory was empty and non-persistent, with later integrations deferred. Current persistence, scanning, recognition and reminders are described above; authentication and Firebase remain unimplemented, and no third-party packages are required.

## Run

1. Open `PantryPulse.xcodeproj` in Xcode.
2. Select the existing `PantryPulse` scheme and an available iPhone simulator.
3. Build and run. The app target supports iOS 17.6 and later.

The project was created with Xcode 26.3 and uses file-system-synchronized groups. Existing test targets still require iOS 26.2 or later; use a compatible simulator for tests. Signing settings and bundle identifier (`PantryPulse.PantryPulse`) are unchanged.

Simulator build without device signing:

```sh
xcodebuild -project PantryPulse.xcodeproj -scheme PantryPulse \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/PantryPulse-Day1 CODE_SIGNING_ALLOWED=NO build
```

## Structure

```text
PantryPulse/
  App/                         App entry, tab navigation, dependency ownership
  DesignSystem/                Named tokens, reusable styles, and nine visual components
  Features/
    Home/                      Dashboard summaries, Use First and recently added sections
    Pantry/                    Inventory view and observable presentation state
    AddFood/                   Shared Add/Edit form and native photo selection
    Onboarding/                Three-page introduction and reusable replay flow
    Scan/                      Scan choices and honest future-feature destinations
    UseFirst/                  Expiry priority, unknown dates and expired items
    FoodDetails/               UUID-backed details and shared-form editing
    Insights/                  Recorded consumption/waste charts and activity
    Settings/                  Reminder preferences, introduction replay and About
    Shared/                    Food rows, photo loading, and shared presentation
  Persistence/                 Core Data controller, model, and repository
  Services/                    Photos, product lookup/OCR, expiry and local reminders
  Models/                      Framework-independent pantry value types
  Resources/
    Assets.xcassets/            Existing assets and Figma orange AccentColor
    PreviewContent/            Debug-only sample data and preview definitions
Tests/
  PantryPulseTests/             Existing Swift Testing target
  PantryPulseUITests/           Existing XCTest UI target
docs/                          Coursework proposal
ml-training/                   Existing location reserved for later model work
```

Swift sources beneath `PantryPulse/` are included automatically by the existing synchronized app group. The two synchronized test groups now point to `Tests/`; their target identities are unchanged. There is no new workspace, package, or generated project.

## Data and dependency boundaries

Current flow: `PantryPulseApp → PersistenceRootView → AppLaunchView → AppRootView → Home / Pantry`.

`StoredPantryLaunchView` constructs one repository-backed `PantryViewModel`. Home and Pantry share saved value snapshots and refresh on repository changes. Core Data objects, validation, mapping, and writes stay behind `PantryRepositoryProtocol`; views receive Swift value types. Add/Edit share one form and preserve draft UUIDs across retries. Photos use local files through `FoodPhotoStorage`.

### Navigation

`App/Navigation/AppNavigation.swift` owns the selected `AppTab` and an independent typed `[AppRoute]` path for each tab. `AppRootView` creates exactly one `NavigationStack` per tab and resolves every pushed destination. Feature views receive action closures and do not manage route paths or create nested stacks. Native back navigation updates the bound path. Paths and shared pantry state survive tab switches for the lifetime of the app window; cold-launch restoration is not implemented.

Home's **Use First → See all** opens the active expiry-priority list, with unknown dates and expired records separated. Add Food opens the working form from Home, Pantry, and Scan → Enter Manually. Food cards resolve Details and Edit by UUID. Delete requires confirmation; missing records do not recreate themselves. Profile selects Settings. Default-storage preferences remain marked as a later-phase capability; recognition opens the photo classifier. Expiry reminders are configured through Settings or the Home bell. Barcode lookup now has a working confirmation flow.

The original model and `Item.timestamp` entity remain for migration compatibility. Production opens SQLite without seeding data. Tests use isolated in-memory or temporary SQLite stores; UI tests use unique preference suites and temporary photo roots. `PantryPreviewData` remains under `#if DEBUG` and is used only by previews.

## Design reference

Current [Figma design](https://www.figma.com/design/gN8iVpNHzWntSCgi7bIDoy/PantryPulse-Smart-Food-Inventory), inspected through MCP. This is the active design reference; the proposal links to an earlier file.

| Screen | Figma node |
|---|---|
| Welcome / PantryPulse Onboarding 3 | `5:3470` |
| AI Introduction / PantryPulse Onboarding 4 | `5:3352` |
| Home Dashboard | `3:319` |
| My Pantry | `3:593` |
| Empty Pantry | `3:2910` |

Figma uses Plus Jakarta Sans and orange `#FF9A62`, with an ivory `#F6F2EB` background. The reusable design system now exposes named asset colours, Dynamic Type typography with a Plus Jakarta Sans fallback strategy, shared spacing/card styles, and nine visual components. Custom font files are not supplied, so system fonts remain active. Home and Pantry reuse these components. Existing PNG exports are preserved and copied into food image sets for previews; the missing Empty Pantry shelf illustration was exported directly from Figma.

See [Design system usage](docs/DESIGN_SYSTEM.md) for component APIs, colour values, preview instructions, and the distinction between Figma values and native accessibility/dark-appearance adaptations.

There are no configured prototype connections. Navigation follows the inspected Home tab bar (`3:565`): Home, Pantry, central Scan, Insights, and Settings (Figma labels the last tab Profile). Use First is consistently a Home destination rather than replacing Insights as one mockup does. Scan offers working barcode lookup and manual entry, plus photo-based recognition. Barcode scanning and Add/Edit → Take Photo request camera permission; onboarding requests no permissions. Onboarding uses the inspected Welcome (`5:3470`), Expiry Notifications (`3:112`), and AI Introduction (`5:3352`) layouts in the requested order.

The native tab bar uses a central filled camera-circle SF Symbol. On iOS 17–18 it requests the Figma charcoal background token (`#242424`, 95% opacity) with the orange accent. On iOS 26 it keeps the system's adaptive Liquid Glass appearance and uses the accessible orange/brown action tint; forcing a dark toolbar scheme produced white labels over light glass during simulator verification. SwiftUI/iOS controls geometry and item sizing; the design's oversized 52-point orange camera button and exact capsule are not custom-overlaid. This retains native tab selection, accessibility, and safe-area behavior. Authentication designs do not add an authentication requirement to this local-first coursework app.

## Verification and next steps

See `IMPLEMENTATION_PLAN.md` for the seven-day sequence and historical verification. Day 3 results are recorded in `docs/DAY3_BARCODE.md`: Debug/Release builds passed, 57 unit tests passed, and focused Simulator checks verified onboarding, navigation, live barcode lookup, confirmed inventory/photo saving and relaunch persistence. The user verified product retrieval on an iPhone 13 and confirmed capture stops after leaving Scan. Physical permission denial, torch, landscape capture and individual barcode variants remain unverified. The pre-commit cleanup is recorded in `docs/DAY3_CLEANUP.md`.

## Home and Pantry screens

- Home displays actual active inventory counts, expiry classifications, recently added items, and upcoming Use First previews. The segmented gauge shows fresh green, soon amber, urgent/expired red, and unknown grey proportions; empty inventory is grey with zero items.
- Pantry combines name search, category filtering, and four sort modes over saved active records. Filters survive tab switches. Empty inventory and no matching results have distinct states.
- Food cards adapt to compact widths and accessibility text sizes. Saved local photos are shown when available; neutral placeholders replace absent images. Preview stock assets are never assigned to production records.
- Shared calendar-day expiry rules are expired (<0), urgent (0–1), expiring soon (2–3), fresh (4+), or unknown. Expired records count separately from urgent and are excluded from upcoming Use First suggestions. These are date-based labels, not ML or food-safety assessments.
- Production never seeds inventory. Partial usage, receipt scanning, and recipe recommendations remain deferred; no fake predictions or savings are displayed.

Preview variants and design adaptations are documented in [screen implementation notes](docs/SCREENS.md).

## Onboarding and supporting screens

- `AppLaunchView` gates the dashboard with `@AppStorage("pantrypulse.onboardingCompleted")`. Both Skip and the final Get Started action persist completion; merely viewing or swiping pages does not. Interrupted onboarding starts from the first page on the next launch.
- The native paging `TabView` supports swipes, Continue, tappable page indicators, and Skip. Explicit page transitions respect Reduce Motion. Page content scrolls at larger text sizes while the completion controls stay available.
- Existing welcome and recognition exports are preserved and copied into named image sets; the expiry photograph is exported from Figma. Photography is decorative, with no simulated recognition percentages, expiry values, or notifications. Reminder copy points to opt-in Settings; recognition copy asks users to review and correct suggestions.
- Settings uses native grouped rows, displays the current implementation status, and offers a working About page and Review Introduction. Replaying dismisses back to Settings and does not change completion or inventory. Appearance follows the system. Expiry reminders have working opt-in controls; unfinished default-storage preferences lead to explicit explanations.
- Insights shows recorded history charts and an empty-history state with a working link to Pantry. No savings, environmental-impact or tier claims are invented. Scan choices adapt the inspected scanner frame; Figma does not contain a separate Scan choices frame or an empty Insights variant.
- Onboarding completion uses AppStorage; inventory uses Core Data and photos use local files. Onboarding requests no permissions. Accounts and Face ID remain deferred.

UI tests isolate preferences with a unique `PantryPulse.UITests.*` UserDefaults suite passed in `PANTRYPULSE_UI_TEST_DEFAULTS`. This injection is DEBUG-only, never seeds inventory, and does not reset normal app preferences. Repeated launches in a persistence test use the same suite.

## Unified product identification

Scan Product supports EAN-13, EAN-8, UPC-E, UPC-A representations, Code 128 and ITF-14 when available in Vision. Raw values and leading zeros are retained. Recognized GTIN carriers receive checksum validation; ordinary Code 128 text is opaque.

Lookup checks the confirmed local catalogue before Open Food Facts. Injectable licensed-provider and exact-barcode search boundaries are available but no additional service is configured, paid API activated, secret embedded, or retail website scraped. Missing records, network failures and API failures have distinct states. Unknown products offer packaging OCR, manual details and retry through the same confirmation flow.

Successful food confirmation saves reusable metadata in `Application Support/ProductCatalogue/Products.json`, with independently owned catalogue photos. Purchase dates, expiry dates and remaining quantities stay in inventory. OCR suggestions are editable and unverified; reusable package size and per-purchase label quantity require separate explicit choices. Barcode confirmation never automatically creates inventory. All eight requested food categories are available; the older Snacks value remains readable/selectable for existing inventory compatibility.

The earlier experimental retailer selector, parser and seeded mappings have been superseded by this unified flow. Existing legacy catalogue files are left untouched; they cannot safely be migrated into barcode records because they contain only retailer product codes. See [identification evidence and limitations](docs/PRODUCT_IDENTIFICATION.md).

Unified-flow verification: final Debug and Release builds passed, 70 unit tests passed, and all 20 UI cases have passing results across the full run and two corrected focused reruns. The user confirmed packaging OCR text extraction and field selection on iPhone 13. See the identification report for initial failures, actual provider coverage and physical-test limits.

## UI and camera refinements

Onboarding imagery now extends behind the status bar. Recognize Food opens capture immediately on a device; captured/library photos are classified automatically and open one editable Add Food review. Pantry and Insights empty states use a text-focused layout on the warm page background and retain their existing navigation actions. See [implementation and verification](docs/UI_CAMERA_REFINEMENTS.md).

## Day 6 — experimental waste risk

The bundled WasteRiskClassifier now runs genuine on-device tabular inference using saved food and category usage history. Food Details shows Low/Medium/High and factual input context; Use First uses model risk only after expiry day. Missing or unsupported inputs and model failures retain explicit expiry-only behaviour. The model was trained and evaluated on synthetic scenarios, not observed household outcomes. See [schema, evaluation and limitations](docs/WASTE_RISK.md).

Day 6 training verification now includes an executed MLDataTable/MLClassifier export, split-leakage checks and an expiry-only baseline comparison. The full unit suite passes 104 tests; detailed synthetic metrics remain in `docs/WASTE_RISK.md`.

## Day 5–6 cleanup audit

See [cleanup scope and current verification results](docs/DAY5_DAY6_CLEANUP.md). Debug/Release builds and 104 unit tests pass. The full baseline UI run has six failures, and focused navigation/onboarding results vary between runs; this audit does not establish a fully passing UI suite. Supplied training data and checkpoints remain intact (approximately 11 GB); review redistribution rights and commit scope before including them.

## Day 7 — Firebase accounts and optional app lock

Settings → Account & Profile now uses Firebase Authentication for email/password accounts, session restoration, profile names, logout and password reset. Pantry data is isolated by Firebase UID on this device; unowned legacy data is preserved without automatic assignment or upload. Optional Face ID-only locking protects app access separately from account authentication. See [implementation and data policy](docs/AUTHENTICATION.md). This supersedes earlier historical statements that Firebase is unimplemented; existing Firebase package/configuration additions are reused, with no Firestore sync or remote push implementation added here.

## Day 7 — Firestore backend foundation

An account-scoped Firestore snapshot service and owner-only security rules are implemented separately from Core Data. No automatic upload, guest-data merge, cloud restore, photo upload or usage-history sync is enabled. Immutable UUID-backed snapshots accept identical retries and reject conflicting copies. Production deployment and verification remain required. See [backend scope, offline behaviour and verification](docs/FIRESTORE_BACKEND.md) and [deployment instructions](firebase/README.md).

Account screens now follow the Figma form layout. Settings shows the signed-in user's name (or email if no display name is saved). Signing out returns directly to authentication while preserving onboarding completion and account-specific local records.

## Account isolation update

Onboarding now leads to required Firebase authentication. Each UID opens its own local Core Data store, photos and product catalogue. Sign-out preserves those files and goes directly to Sign In. The old unowned shared inventory is preserved but quarantined; it is never assigned to the next account. Restoring that legacy inventory requires an explicit ownership-confirmed import, which is not implemented. See [account storage and Face ID policy](docs/AUTHENTICATION.md) and [verification](DAY7_AUDIT.md).

Profile supports real name updates, password resets and a per-account, Face ID-only app lock. Face ID is separate from Firebase authentication. Full multi-device synchronization is not claimed.
