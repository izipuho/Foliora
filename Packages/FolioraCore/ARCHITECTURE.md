# FolioraCore Architecture Boundaries

This package is shared by app-family targets. Keep it small, explicit, and reusable.

## Dependency Direction

```text
App Targets
    |
    v
DesignSystem / CollectionDomain / Core
    |
    v
no reverse dependencies
```

Package targets must not import app targets or app-specific folders.

## Core

Responsibility:
- Pure Swift utilities and small reusable helpers.
- Code with no product, UI, storage, or collection semantics.

Allowed dependencies:
- Swift standard library.
- Foundation only when the helper genuinely needs it.

Forbidden dependencies:
- SwiftUI, UIKit, SwiftData.
- App features, navigation, storage, networking.
- Collection, books, bells, or other product-specific semantics.

Allowed examples:
- String/file-name sanitizers.
- Date or formatter helpers.
- Small generic algorithms.

Forbidden examples:
- Bell recognition helpers.
- Collection item models.
- View modifiers or colors.
- Repository, persistence, or API clients.

## DesignSystem

Responsibility:
- Reusable visual language shared by app-family targets.
- Shared modifiers, styles, typography, spacing, elevation, and design tokens.

Allowed dependencies:
- SwiftUI.
- Foundation when needed for UI support.

Forbidden dependencies:
- Domain logic.
- Storage, network, import/export, or persistence logic.
- App navigation graphs or feature screens.

Allowed examples:
- `ViewModifier`s.
- Shadow/elevation styles.
- Spacing, corner radius, typography tokens.
- Generic visual components with no feature behavior.

Forbidden examples:
- Bell list cards with bell-specific fields.
- SwiftData queries.
- Upload/download state.
- Navigation destinations.

## CollectionDomain

Responsibility:
- Platform-neutral collection abstractions.
- Generic models and contracts shared across collection types.

Allowed dependencies:
- Swift standard library.
- Foundation for value types such as `UUID` and `Date`.

Forbidden dependencies:
- SwiftUI, UIKit, SwiftData.
- Persistence implementation.
- Bells/books/stamps/coins-specific semantics.
- Feature workflows or UI state.

Allowed examples:
- Media references.
- Attachment types.
- Generic item identifiers.
- Generic metadata structures.

Forbidden examples:
- `BellItem`, `BookItem`, or recognition-specific models.
- SwiftData entities.
- View models.
- Import/export actors.

## How To Decide Where New Code Belongs

Ask these questions in order:

1. Is it app-specific behavior or screen flow?
   Keep it in the app target.
2. Is it reusable visual styling with no domain behavior?
   Put it in `DesignSystem`.
3. Is it a collection concept that applies across collection types?
   Put it in `CollectionDomain`.
4. Is it a pure generic helper with no collection meaning?
   Put it in `Core`.
5. Would moving it force a shared module to import app code?
   Do not move it.

Prefer leaving code local until there is a clear second use.

## Red Flags

- A shared package target imports an app target or app folder.
- SwiftUI appears in `Core` or `CollectionDomain`.
- SwiftData appears anywhere in `FolioraCore`.
- A bells/books-specific model lands in `CollectionDomain`.
- `Core` becomes a dumping ground for unrelated helpers.
- Shared modules start depending on each other without a clear reason.
- A reusable style grows feature state, navigation, storage, or networking.
- Moving code requires copying an existing feature screen into another target.
