# Foliora

## Bells
<img src="Catalog/Resources/Assets.xcassets/MedalionBell.imageset/Medalion%20Bell.png"
     alt="Foliora Bells icon"
     width="128">

Foliora is a native SwiftUI iOS app for cataloging home collections. The active product target is **Foliora Bells**: an offline-first catalog for bell collections with homes, storage locations, photos, search, import/export, and iCloud sharing built on Core Data + CloudKit.

The repository also contains a small bell-recognition/debug target and a local PyTorch-to-Core ML training pipeline for experimenting with bell tag decisions. The production app now uses Apple's local Vision, Foundation Models, and Translation frameworks for photo suggestions.

## Product Features

### Homes and Storage

- Create, edit, and delete homes.
- Maintain owner-managed storage hierarchies for each home.
- Assign collections and bell items to storage locations.
- View storage/location context from the home screens.

### Collections

- Create and edit collections attached to homes.
- Fixed collection kind support, with bells as the implemented catalog type.
- Collection cards include item counts, home context, background styles, and sharing status.
- Shared collections can be deleted by owners or left by participants.

### Bells Catalog

- Add, edit, delete, and browse bell records.
- Store title, notes, acquisition year, condition, acquisition method, material, custom material, origin place, tags, storage location, creator, and media assets.
- Add bells one at a time or create batches from multiple selected photos.
- Browse with multiple card layouts, pinch-to-change layout, search, filters, sorting, jump navigation, and selection mode.
- Filter by completeness and attributes such as origin, year, city, storage, notes, tags, material, country, condition, and acquisition method.
- Analyze photos locally with Vision and Apple Foundation Models to detect the main object, read visible text, suggest titles, notes, materials, condition, acquisition year, origin hints, tags, and visual keywords.
- Translate photo-analysis suggestions into the user's app language when Apple Translation support is available, with lower-confidence tag suggestions visually de-emphasized.
- Warn when the analysis does not detect a bell in the selected photo.

### Data Portability

- Export selected collections to a `.zip` archive.
- Import Foliora archive files and choose which collections to restore.
- Archive payloads include JSON metadata and media files.

### iCloud and Sharing

- Core Data uses separate private and shared persistent stores backed by CloudKit.
- Collections are the sharing boundary.
- The app handles CloudKit share invitations and provides collection sharing UI.
- Debug builds include Cloud sync diagnostics and a purge tool for development data resets.

## Repository Structure

```text
Catalog/                         Main Foliora app source
  App/                           App entry point, app delegate, dependency container, share scene delegate
  Core/                          Navigation, design system, shared UI, media helpers, photo analysis
  Data/
    CoreData/                    Core Data + CloudKit stack and model
    ImportExport/                Archive import/export document, JSON, and media pipeline
    Repositories/                Repository protocol and Core Data implementation
  Domain/                        Collection, item, bell, place, media, and sharing models/services
  Features/
    Bells/                       Bell catalog list, detail, editor, batch add, and analysis UI
    Books/                       Placeholder library module
    Collections/                 Collection list, editor, sharing, origin map, shell views
    Home/                        Homes and storage-location UI
    Settings/                    Import/export, CloudKit status, photo analysis, diagnostics
  Resources/                     Assets and localized strings

BellRecognition/                 Standalone bell-recognition SwiftUI/debug app
BellRecognitionDebugML/          Debug UI for ML dataset preparation
ml/                              PyTorch training and Core ML export pipeline
docs/                            Architecture and data-model notes
```

## Data Model and Persistence

The live app repository is `CoreDataCatalogRepository`, which implements the `CatalogRepository` protocol. The app initializes an `NSPersistentCloudKitContainer` through `FolioraCoreDataStack` and injects a repository from `AppContainer`.

Core Data currently stores the main app graph:

- `HomeEntity`
- `LocationEntity`
- `CollectionEntity`
- `BellEntity`
- `PlaceEntity`
- `MediaAssetEntity`
- tag-related entities

CloudKit integration is configured through two persistent stores:

- `Private.sqlite` for the user's private database.
- `Shared.sqlite` for the shared database.

See `docs/cloudkit-data-model.md` for the CloudKit-oriented record model and collaboration boundaries.

## ML Pipeline

The `ml/` folder contains a local multimodal classifier pipeline:

```text
crop image + tag text + vision confidence -> keep / rejectNoise / rejectWrong
```

It trains in PyTorch and exports a Core ML `.mlpackage`. See `ml/README.md` for setup, training, export, and runtime input details.

## Development

### Requirements

- Xcode with iOS 26 SDK support.
- Device or simulator runtime with Apple Foundation Models and Translation framework support for semantic photo suggestions and localized suggestion text.
- An Apple developer team with iCloud/CloudKit capabilities for device or CloudKit testing.
- Python 3 for the optional ML tools.

## Notes

- The app is offline-first: local Core Data writes are the primary interaction path, with CloudKit synchronization handled by the persistent container.
- Photo analysis is designed to run locally through Apple system frameworks; suggested fields remain user-reviewed before they are saved.
- Sharing is collection-scoped; home/location management remains owner-controlled reference data.
- Books, coins, and stamps assets are present, but bells are the implemented catalog experience in the current codebase.
