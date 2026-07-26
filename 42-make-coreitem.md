# План миграции на общую модель `Item`

## [ ] Этап 1. Привести Core Data к целевой модели

**Меняется:**

- `Foliora.xcdatamodeld`

Сразу привести модель к финальному виду:

- создать абстрактную `ItemEntity`;
- сделать `BellEntity` её наследником;
- перенести в `ItemEntity` все общие attributes и relationships;
- заменить `BellTagEntity` на `ItemTagEntity`;
- сразу использовать общие relationship'ы (`items`, `item`);
- задать `Renaming ID` там, где это поддерживает lightweight migration.

После этого Core Data должна соответствовать архитектуре, под которую дальше будет переводиться код.

---

## [ ] Этап 2. Привести доменную модель к общей структуре

**Меняется:**

- `ItemModels.swift`
- `BellItem.swift`

Выполнить одновременно:

- перенести `originPlaceID` из `BellDetails` в `Item`;
- выделить `ItemRecord`;
- сделать `BellRecord` композицией из `ItemRecord` и `BellDetails`;
- сохранить прокси-свойства, чтобы не менять UI.

---

## [ ] Этап 3. Перевести все mapper'ы на `ItemRecord`

**Меняется:**

- `CatalogSnapshot.swift`
- `BellLookupSnapshot.swift`
- `CoreDataCatalogRepository.swift`
- `CatalogImportExportActor.swift`

Во всех местах формировать:

```text
BellRecord
├── ItemRecord
└── BellDetails
```

Использовать новую структуру модели без изменения поведения приложения.

---

## [ ] Этап 4. Разделить запись общей и предметной частей

**Меняется:**

- `CoreDataCatalogRepository.swift`

Разделить запись на два независимых mapper'а:

```swift
apply(_ itemRecord: ItemRecord, to:)
apply(_ details: BellDetails, to:)
```

Общий mapper должен работать только с полями `ItemEntity`, предметный — только с полями `BellEntity`.

---

## [ ] Этап 5. Разделить чтение общей и предметной частей

**Меняется:**

- `BellEntity+Mapping.swift`

Выделить независимые преобразования:

- `ItemEntity ⇄ ItemRecord`;
- `BellEntity ⇄ BellDetails`.

`BellRecord` должен собираться композиционно.

---

## [ ] Этап 6. Обобщить контракт репозитория

**Меняется:**

- `CatalogRepository.swift`
- `CoreDataCatalogRepository.swift`

Сохранение оставить предметным:

```swift
saveBellRecord(_:)
```

Удаление сделать общим:

```swift
deleteItemRecord(itemID:)
```

---

## [ ] Этап 7. Обновить формат импорта и экспорта

**Меняется:**

- `CatalogImportExportActor.swift`

Разделить transfer-модель:

```text
BellTransferRecord
├── item
└── details
```

Экспорт должен формировать новый формат.

Импорт должен поддерживать:

- новый формат;
- старый формат для обратной совместимости.

---

## [ ] Этап 8. Адаптировать загрузку каталога и поиск

**Меняется:**

- `CatalogSnapshot.swift`
- `BellLookupSnapshot.swift`

Сохранить загрузку через `BellEntity`, но использовать новые общие и предметные mapper'ы без дублирования логики.

---

## [ ] Этап 9. Финальная проверка

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
