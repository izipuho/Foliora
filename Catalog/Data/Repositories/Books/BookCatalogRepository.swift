import Foundation

/// Defines the book-specific repository operations.
@MainActor
protocol BookCatalogRepository {
    func saveBookRecord(_ book: BookRecord)
    func saveBookRecords(_ books: [BookRecord])
    func saveBookSeries(_ series: BookSeries)
    func deleteBookRecord(bookID: UUID)
}

extension BookCatalogRepository {
    func saveBookRecords(_ books: [BookRecord]) {
        books.forEach(saveBookRecord)
    }
}
