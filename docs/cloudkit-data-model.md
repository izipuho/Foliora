# CloudKit Data Model

## Source of Truth

The app is moving to a CloudKit-first architecture.

- CloudKit is the primary source of truth.
- The shared database is the main collaboration surface.
- The private database can later hold user-specific drafts, settings, and offline staging.
- The public database is not required for the current product shape.

## Collaboration Boundary

Collections are shared.

- Collaborators can create and edit items inside a shared collection.
- Collaborators can change an item's assigned storage location.
- Collaborators cannot create, rename, reorder, or delete home locations.
- Home and location hierarchy remain owner-managed reference data.

## Record Types

### `Home`

Owner-managed container for locations and collections.

Fields:

- `name: String`
- `notes: String`
- `ownerUserID: String`
- `createdAt: Date`
- `updatedAt: Date`

### `Location`

Owner-managed node inside the storage hierarchy.

Fields:

- `homeRef: CKRecord.Reference`
- `parentLocationRef: CKRecord.Reference?`
- `name: String`
- `kind: String`
- `sortOrder: Int64`
- `notes: String`

### `Collection`

Fixed collection definition inside a home.

Fields:

- `homeRef: CKRecord.Reference`
- `kind: String`
- `name: String`
- `status: String`
- `sortOrder: Int64`

### `Item`

Shared base record for any collectible item.

Fields:

- `collectionRef: CKRecord.Reference`
- `locationRef: CKRecord.Reference?`
- `title: String`
- `notes: String`
- `year: Int64?`
- `condition: String`
- `acquisitionMethod: String`
- `createdByUserID: String`
- `createdAt: Date`
- `updatedAt: Date`

### `BellDetails`

Bell-specific extension record linked to a base item.

Fields:

- `itemRef: CKRecord.Reference`
- `originPlaceRef: CKRecord.Reference?`
- `material: String`
- `customMaterialName: String?`

### `Place`

Normalized place record used by bell origin and future collection types.

Fields:

- `displayName: String`
- `countryCode: String`
- `countryName: String`
- `regionName: String?`
- `cityName: String?`
- `latitude: Double?`
- `longitude: Double?`

### `MediaAsset`

Media metadata plus file payload for an item.

Fields:

- `itemRef: CKRecord.Reference`
- `kind: String`
- `assetFile: CKAsset`
- `fileName: String`
- `sortOrder: Int64`
- `createdAt: Date`

## Relationships

- `Home` -> many `Location`
- `Home` -> many `Collection`
- `Collection` -> many `Item`
- `Item` -> zero or one `BellDetails`
- `Item` -> many `MediaAsset`
- `BellDetails` -> zero or one `Place`

## Enum Storage

Enums are stored as stable technical keys, not localized strings.

Examples:

- `good`
- `needs_restoration`
- `bought`
- `bells`
- `shelf`

Localization happens only in the app UI layer.

## Media Strategy

- Files are stored in CloudKit as `CKAsset`.
- Metadata stays in a separate `MediaAsset` record.
- `kind` distinguishes `photo`, `document`, and `model3D`.
- `sortOrder` defines stable presentation order.

## Current Implementation Strategy

The current repository layer is being switched to a CloudKit-first entry point while the sync engine is still under construction.

- `CloudKitCatalogRepository` is the live app repository.
- `InMemoryCatalogRepository` remains the preview and fallback source during migration.
- The next step is replacing fallback reads with real CloudKit fetch/save flows.
