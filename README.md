# Foliora

Foliora is a native SwiftUI iOS app for cataloging home collections. The active product target is **Foliora Bells**: an offline-first catalog for bell collections with homes, storage locations, photos, search, import/export, and iCloud sharing built on Core Data + CloudKit.

The repository also contains a small bell-recognition/debug target and a local PyTorch-to-Core ML training pipeline for experimenting with bell tag decisions.

## Current State

- SwiftUI app target: `Foliora Bells`.
- Persistence: Core Data through `NSPersistentCloudKitContainer`.
- Sync/sharing: private and shared CloudKit stores using container `iCloud.com.izipuho.FolioraBells`.
- Main feature area: bells catalog.
- Supporting areas: homes, storage maps/locations, collections, settings, import/export, CloudKit diagnostics.
- Experimental areas: standalone bell-recognition/debug apps and local ML training utilities.

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
- Analyze photos locally with Vision OCR/object signals to suggest tags and visual keywords.

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
    Settings/                    Import/export, CloudKit status, diagnostics
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
- An Apple developer team with iCloud/CloudKit capabilities for device or CloudKit testing.
- Python 3 for the optional ML tools.

### Open the App

```sh
open Foliora.xcodeproj
```

Select the `Foliora Bells` scheme and run on a simulator or device.

### Useful Checks

```sh
xcodebuild -project Foliora.xcodeproj -scheme "Foliora Bells" -destination 'platform=iOS Simulator,name=iPhone 17' build
```

For ML tooling:

```sh
python3 -m venv .venv-ml
source .venv-ml/bin/activate
pip install -r ml/requirements.txt
python ml/train.py --dataset-dir "Example photos/dataset"
python ml/export_coreml.py
```

## Notes

- The app is offline-first: local Core Data writes are the primary interaction path, with CloudKit synchronization handled by the persistent container.
- Sharing is collection-scoped; home/location management remains owner-controlled reference data.
- Books, coins, and stamps assets are present, but bells are the implemented catalog experience in the current codebase.
