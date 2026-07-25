# План миграции на общую модель `Item`

## Этап 1. Переименовать `BellTagEntity` в `ItemTagEntity`

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

## Этап 2. Перенести `originPlaceID` из `BellDetails` в `Item`

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

## Этап 3. Выделить `ItemRecord`

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

## Этап 4. Перевести mapper-ы на `ItemRecord`

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

## Этап 5. Добавить абстрактную `ItemEntity`

**Меняется только:**

- `Foliora.xcdatamodeld`

Создать:

```text
ItemEntity
Abstract = YES
```

Пока без изменения родителя `BellEntity`.

Перенести в неё копии общих attributes и relationships, но ещё не удалять их из `BellEntity`.

Общие attributes:

- `id`
- `title`
- `notes`
- `acquiredYear`
- `createdAt`
- `conditionRaw`
- `acquisitionMethodRaw`
- `isFavorite`
- `createdBy`

Общие relationships:

- `collection`
- `location`
- `collectionLocation`
- `originPlace`
- `mediaAssets`
- `tags`

На этом промежуточном шаге модель не должна содержать дублирующиеся inherited-поля. Поэтому фактический перенос полей и установка parent лучше выполнять одной атомарной правкой модели на следующем этапе. Этот этап фактически является подготовкой схемы и фиксацией состава полей.

---

## Этап 6. Сделать `BellEntity` наследником `ItemEntity`

**Меняется только:**

- `Foliora.xcdatamodeld`

Действия одной атомарной правкой:

1. Установить:

```text
BellEntity.parentEntity = ItemEntity
```

1. Перенести перечисленные общие attributes и relationships из `BellEntity` в `ItemEntity`.

2. В `BellEntity` оставить только:

- `materialRaw`
- `customMaterialName`

1. Для переносимых свойств сохранить исходные имена и типы.

2. Для миграции задать соответствующие `Renaming ID`, если Xcode не сможет вывести перенос автоматически.

Особенно важно проверить миграцию отношений и CloudKit-схему. Контейнер использует автоматическую lightweight migration для двух persistent stores — private и shared.

---

## Этап 7. Обобщить отношения Core Data

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

## Этап 8. Обобщить контракт репозитория

**Меняется:**

- `CatalogRepository.swift`
- `CoreDataCatalogRepository.swift`

Добавить общий контракт:

```swift
func saveItemRecord(_ item: ItemRecord)
func deleteItemRecord(itemID: UUID)
```

Но `ItemRecord` не содержит `BellDetails`, поэтому общий метод сам по себе не может полноценно сохранить `BellEntity`.

Практический вариант:

```swift
func saveBellRecord(_ bell: BellRecord)
func deleteItemRecord(itemID: UUID)
```

То есть:

- удаление становится общим;
- сохранение пока остаётся типизированным по предмету коллекции.

Позже для других типов появятся:

```swift
func saveCoinRecord(_ coin: CoinRecord)
func saveStampRecord(_ stamp: StampRecord)
```

Не стоит вводить `saveItemRecord`, пока нет отдельного механизма сохранения subtype details.

Текущий протокол полностью привязан к `BellRecord`.

## Этап 9. Разделить `apply(_:to:)` на общую и предметную части

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

## Этап 10. Обобщить snapshot mapping

**Меняется:**

- `CatalogSnapshot.swift`
- `BellLookupSnapshot.swift`

Выделить общий mapper:

```swift
private func itemRecord(
    from entity: NSManagedObject,
    ...
) -> ItemRecord
```

Он должен собирать:

- `Item`
- место происхождения;
- место хранения;
- путь хранения;
- медиа;
- избранное;
- автора;
- теги.

Отдельный mapper колокольчика:

```swift
private func bellRecord(
    from entity: NSManagedObject,
    ...
) -> BellRecord
```

должен делать только:

```swift
BellRecord(
    itemRecord: itemRecord(from: entity, ...),
    details: bellDetails(from: entity)
)
```

Общая логика не должна оставаться продублированной между `CatalogSnapshot` и `BellLookupSnapshot`.

Если сразу вынести mapper в отдельный тип невозможно без расширения области изменений, сначала привести оба файла к одинаковому разделению:

```text
entity → ItemRecord
entity → BellDetails
ItemRecord + BellDetails → BellRecord
```

А уже затем вынести повторяющийся код.

---

## Этап 11. Обобщить transfer-модели

**Меняется:**

- `CatalogImportExportActor.swift`

Ввести общую модель:

```swift
struct ItemTransfer: Codable {
    let id: UUID
    let collectionID: UUID
    let title: String
    let notes: String?
    let acquiredYear: Int?
    let conditionRaw: String?
    let acquisitionMethodRaw: String?
    let locationID: UUID?
    let collectionLocationID: UUID?
    let originPlaceID: UUID?
    let isFavorite: Bool
    let createdAt: Date
    let createdBy: String
    let tags: [String]
    let mediaAssets: [MediaAssetTransfer]
}
```

И предметную часть:

```swift
struct BellDetailsTransfer: Codable {
    let materialRaw: String
    let customMaterialName: String?
}
```

Итоговая модель:

```swift
struct BellTransfer: Codable {
    let item: ItemTransfer
    let details: BellDetailsTransfer
}
```

Для обратной совместимости старый плоский формат нельзя просто удалить.

Нужен custom `init(from:)`, который поддерживает оба варианта:

1. новый вложенный формат:

```json
{
  "item": { ... },
  "details": { ... }
}
```

1. старый плоский формат:

```json
{
  "id": "...",
  "collectionID": "...",
  "materialRaw": "...",
  ...
}
```

Экспорт после миграции должен писать только новый формат. Импорт должен принимать оба.

---

## Этап 12. Обобщить import/export persistence

**Меняется:**

- `CatalogImportExportActor.swift`

Разделить запись импортируемого объекта:

```swift
private func apply(
    _ item: ItemTransfer,
    to entity: NSManagedObject,
    context: NSManagedObjectContext
)

private func apply(
    _ details: BellDetailsTransfer,
    to entity: NSManagedObject
)
```

Общая часть сохраняет:

- общие attributes;
- отношения коллекции;
- места;
- теги;
- медиа;
- избранное;
- автора.

Предметная часть сохраняет:

- материал;
- пользовательское название материала.

Поиск существующего объекта должен выполняться по `ItemEntity.id`, а не по предметной модели как концепции:

```swift
fetchRequest(entityName: "ItemEntity")
```

Но создавать по-прежнему нужно конкретную сущность:

```swift
NSEntityDescription.insertNewObject(
    forEntityName: "BellEntity",
    into: context
)
```

При этом нужно проверить, поддерживает ли fetch абстрактной сущности поиск по наследникам в текущей Core Data-конфигурации. Если это создаёт проблемы с двумя store или CloudKit, оставить fetch по `BellEntity` до появления второго subtype.

Обобщать fetch заранее необязательно. Важнее разделить общий и предметный persistence-код.

## Этап 13. Проверка миграции

**Проверяются:**

- `Foliora.xcdatamodeld`
- `CoreDataCatalogRepository.swift`
- `CatalogSnapshot.swift`
- `BellLookupSnapshot.swift`
- `CatalogImportExportActor.swift`

После завершения миграции проверить:

- lightweight migration существующей базы;
- работу private и shared stores;
- корректность чтения и записи `BellRecord`;
- создание, редактирование и удаление колокольчиков;
- импорт и экспорт каталога;
- отсутствие потери данных и появления дубликатов;
- совместимость существующего UI без дополнительных изменений.

Только после успешного прохождения всех проверок переход можно считать завершённым.
