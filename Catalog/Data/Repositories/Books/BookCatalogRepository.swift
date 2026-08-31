import Foundation

/// Defines the book-specific repository operations.
@MainActor
protocol BookCatalogRepository {
    func saveBookRecord(_ book: BookRecord)
    func saveBookRecords(_ books: [BookRecord])
    func saveBookSeries(_ series: BookSeries)
    func deleteBookSeries(seriesID: UUID)
    func savePublisher(_ publisher: Publisher)
    func deletePublisher(publisherID: UUID)
    func savePerson(_ person: Person)
    func deletePerson(personID: UUID)
    func deleteBookRecord(bookID: UUID)
}

extension BookCatalogRepository {
    func saveBookRecords(_ books: [BookRecord]) {
        books.forEach(saveBookRecord)
    }
}
