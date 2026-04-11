# Catalog

A native SwiftUI iOS app for cataloging home collections.

The project is currently structured around a universal architecture:

- fixed collection types defined in code;
- a dedicated UI for each collection type;
- a domain model for collections, access roles, and collaborators;
- a `Repository` layer that can later be backed by `SwiftData` and `CloudKit`;
- the first working feature for the bells catalog;
- a placeholder module for the home library.

## Architectural Decisions

- top-level entity: `Collection`;
- access model: invitation-only;
- roles: `owner`, `editor`, `viewer`;
- the app is designed as `offline-first`;
- future synchronization is planned around `CloudKit`;
- bells and books live as separate modules with different UI.

## Structure

- `Catalog/App` - app entry point and dependency container;
- `Catalog/Core` - navigation and shared UI components;
- `Catalog/Domain` - collection, item, and sharing entities;
- `Catalog/Data` - repository protocols and temporary in-memory data;
- `Catalog/Features` - product modules separated by collection type.

## Next Steps

- local persistence with `SwiftData`;
- sync and sharing through `CloudKit`;
- CRUD flows and photos for bells;
- a full books module;
- an activity log for collection collaborators.
