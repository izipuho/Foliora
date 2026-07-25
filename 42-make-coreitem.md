# План миграции на общую модель `Item`

## [ ] Этап 1. Переименовать `BellTagEntity` в `ItemTagEntity`

**Меняется:**

- `Foliora.xcdatamodeld`
- `CoreDataCatalogRepository.swift`
- `CatalogImportExportActor.swift`

В Core Data:

- переименовать entity `BellTagEntity` → `ItemTagEntity`;
- установить `Renaming ID = BellTagEntity`;
- отношения пока оставить прежними:
  - `bells`;
  - `collection`.

В коде заменить только строковые обращения:

```swift
"BellTagEntity" → "ItemTagEntity"
```

Функции `cleanupBellTags`, `deleteOrphanBellTags`, `tagEntity` на этом шаге можно не переименовывать. Это отдельная косметическая операция.

Сейчас `BellTagEntity` напрямую используется и репозиторием, и импортом/экспортом.

---

## [ ] Этап 2. Перенести `originPlaceID` из `BellDetails` в `Item`

**Меняется:**

- `ItemModels.swift`
- `BellItem.swift`
- `CatalogSnapshot.swift`
- `BellLookupSnapshot.swift`
- `CoreDataCatalogRepository.swift`
- `CatalogImportExportActor.swift`

Целевая модель:

```swift
struct Item {
    let id: UUID
    let collectionID: UUID
    let locationID: UUID?
    let originPlaceID: UUID?
    // остальные общие поля
}

struct BellDetails {
    let itemID: UUID
    let material: BellMaterial
    let customMaterialName: String?
}
```

Все конструкторы `Item` должны получать:

```swift
originPlaceID: originPlaceEntity.map { uuidValue($0, "id") }
```

Из всех конструкторов `BellDetails` этот аргумент удаляется.

На уровне Core Data пока ничего не меняется: relationship `originPlace` остаётся в `BellEntity`. Меняется только доменная принадлежность свойства.

Сейчас `originPlaceID` собирается внутри `BellDetails` сразу в трёх независимых mapper-реализациях и в импорте/экспорте.

---

## [ ] Этап 3. Выделить `ItemRecord`

**Меняется:**

- `BellItem.swift`
- вероятно `ItemModels.swift`, в зависимости от текущего расположения presentation-моделей.

Целевая структура:

```swift
struct ItemRecord {
    var item: Item
    var originPlace: Place?
    var storageLocation: Location?
    var storagePath: String
    var mediaAssets: [MediaAsset]
    var isFavorite: Bool
    var createdBy: String
    var tags: [String]
}

struct BellRecord {
    var itemRecord: ItemRecord
    var details: BellDetails
}
```

`BellRecord` должен проксировать используемые свойства, чтобы не менять весь UI одновременно:

```swift
extension BellRecord {
    var item: Item {
        get { itemRecord.item }
        set { itemRecord.item = newValue }
    }

    var originPlace: Place? {
        get { itemRecord.originPlace }
        set { itemRecord.originPlace = newValue }
    }

    // аналогично для mediaAssets, isFavorite, createdBy, tags
}
```

Это позволит сохранить текущие вызовы вроде:

```swift
bell.item
bell.mediaAssets
bell.tags
bell.isFavorite
```

и не смешивать архитектурную миграцию с массовой правкой UI.

---

## [ ] Этап 4. Перевести mapper-ы на `ItemRecord`

**Меняется:**

- `CatalogSnapshot.swift`
- `BellLookupSnapshot.swift`
- `CoreDataCatalogRepository.swift`
- `CatalogImportExportActor.swift`

Вместо:

```swift
BellRecord(
    item: ...,
    details: ...,
    originPlace: ...,
    storageLocation: ...,
    ...
)
```

формировать:

```swift
BellRecord(
    itemRecord: ItemRecord(
        item: ...,
        originPlace: ...,
        storageLocation: ...,
        storagePath: ...,
        mediaAssets: ...,
        isFavorite: ...,
        createdBy: ...,
        tags: ...
    ),
    details: ...
)
```

Это нужно сделать отдельным этапом до изменения Core Data, поскольку сейчас логика сборки `BellRecord` дублируется в четырёх файлах.

## [ ] Этап 5. Добавить абстрактную `ItemEntity`

**Меняется:**

- `Foliora.xcdatamodeld`

Создать абстрактную сущность:

```text
ItemEntity
Abstract = YES
```

Сделать `BellEntity` её наследником и перенести в `ItemEntity` все общие attributes и relationships.

В `ItemEntity` должны находиться:

- `id`
- `title`
- `notes`
- `acquiredYear`
- `createdAt`
- `conditionRaw`
- `acquisitionMethodRaw`
- `isFavorite`
- `createdBy`
- `collection`
- `location`
- `collectionLocation`
- `originPlace`
- `mediaAssets`
- `tags`

В `BellEntity` оставить только:

- `materialRaw`
- `customMaterialName`

При необходимости задать `Renaming ID` для корректной lightweight migration.

## [ ] Этап 7. Обобщить отношения Core Data

**Меняется:**

- `Foliora.xcdatamodeld`
- `CoreDataCatalogRepository.swift`
- `CatalogSnapshot.swift`
- `BellLookupSnapshot.swift`
- `CatalogImportExportActor.swift`

Переименовать обратные отношения:

```text
CollectionEntity.bells → items
CollectionLocationEntity.bells → items
ItemTagEntity.bells → items
MediaAssetEntity.bell → item
```

Для каждого переименованного relationship установить старое имя в `Renaming ID`.

После этого заменить обращения:

```swift
relatedObjects(collection, "bells")
→ relatedObjects(collection, "items")

relatedObjects(tag, "bells")
→ relatedObjects(tag, "items")

entity.setValue(bell, forKey: "bell")
→ entity.setValue(item, forKey: "item")
```

На этом же этапе переименовать внутренние функции:

```swift
cleanupBellTags → cleanupItemTags
deleteOrphanBellTags → deleteOrphanItemTags
backfillBellCollectionLocations → backfillItemCollectionLocations
```

Сейчас строковые зависимости `bells` и `bell` находятся в репозитории и импорте/экспорте.

---

## [ ] Этап 8. Обобщить контракт репозитория

**Меняется:**

- `CatalogRepository.swift`
- `CoreDataCatalogRepository.swift`

Сохранение оставить предметным:

```swift
func saveBellRecord(_ bell: BellRecord)
```

Удаление сделать общим:

```swift
func deleteItemRecord(itemID: UUID)
```

`saveItemRecord(_:)` пока не вводить, поскольку `ItemRecord` не содержит `BellDetails` и не может полностью описать `BellEntity`.

## [ ] Этап 9. Разделить `apply(_:to:)` на общую и предметную части

**Меняется:**

- `CoreDataCatalogRepository.swift`

Целевая структура:

```swift
private func apply(
    _ itemRecord: ItemRecord,
    to entity: NSManagedObject
)

private func apply(
    _ details: BellDetails,
    to entity: NSManagedObject
)
```

Общий mapper отвечает за:

- `id`
- `title`
- `notes`
- `acquiredYear`
- `createdAt`
- `conditionRaw`
- `acquisitionMethodRaw`
- `isFavorite`
- `createdBy`
- `collection`
- `location`
- `collectionLocation`
- `originPlace`
- `mediaAssets`
- `tags`

Предметный mapper отвечает только за:

- `materialRaw`
- `customMaterialName`

Сохранение колокольчика:

```swift
apply(bell.itemRecord, to: entity)
apply(bell.details, to: entity)
```

Это позволит следующим типам предметов переиспользовать общую запись без копирования всей логики.

---

## [ ] Этап 10. Разделить общие и предметные мапперы

**Меняется:**

- `BellEntity+Mapping.swift`

Выделить два независимых слоя преобразования:

- `ItemEntity ⇄ ItemRecord`
- `BellEntity ⇄ BellDetails`

Маппинг `BellRecord` должен строиться композиционно:

```text
BellRecord
├── ItemRecord
└── BellDetails
```

Логика чтения и записи общих полей должна находиться только в мапперах `ItemEntity ⇄ ItemRecord`.

Мапперы `BellEntity ⇄ BellDetails` должны работать только со специфичными для колокольчиков полями.

## [ ] Этап 11. Обновить формат импорта и экспорта

**Меняется:**

- `CatalogImportExportActor.swift`

Разделить transfer-модель колокольчика на общую и предметную части:

```text
BellTransferRecord
├── item: ItemTransferRecord
└── details: BellDetailsTransferRecord
```

В `ItemTransferRecord` перенести все общие поля предмета.

В `BellDetailsTransferRecord` оставить только поля, специфичные для колокольчиков:

- `materialRaw`
- `customMaterialName`

Экспорт должен формировать новый вложенный формат.

Импорт должен поддерживать:

- новый вложенный формат;
- старый плоский формат для обратной совместимости.

После декодирования оба формата должны преобразовываться в один `BellRecord`.

## [ ] Этап 12. Адаптировать загрузку каталога и поиск

**Меняется:**

- `CatalogSnapshot.swift`
- `BellLookupSnapshot.swift`

Сохранить загрузку колокольчиков через `BellEntity`, но собирать `BellRecord` через новые общие и предметные мапперы.

В `CatalogSnapshot`:

- загружать `BellEntity`;
- преобразовывать каждую сущность в `BellRecord`;
- не дублировать чтение общих полей предмета.

В `BellLookupSnapshot`:

- оставить поиск по `BellEntity`;
- использовать общий маппинг `ItemEntity ⇄ ItemRecord`;
- добавлять `BellDetails` только при формировании итогового `BellRecord`.

Переход на выборку непосредственно через `ItemEntity` отложить до появления второго типа предметов.

## [ ] Этап 13. Финальная проверка

**Проверяются:**

- `Foliora.xcdatamodeld`
- `CoreDataCatalogRepository.swift`
- `CatalogSnapshot.swift`
- `BellLookupSnapshot.swift`
- `CatalogImportExportActor.swift`

Проверить:

- lightweight migration существующей базы;
- работу private и shared stores;
- создание, редактирование и удаление колокольчиков;
- импорт и экспорт каталога;
- отсутствие потери данных и появления дубликатов.

После успешной проверки миграцию можно считать завершённой.
