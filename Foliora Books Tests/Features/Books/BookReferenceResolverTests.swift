import Foundation
import Testing
@testable import Foliora_Books

struct BookReferenceResolverTests {
    private let testCollectionID = UUID()

    @Test
    func reusesExistingPublisherAndSeriesIgnoringWhitespaceCaseAndDiacritics() {
        let collectionID = UUID()
        let publisher = Publisher(
            id: UUID(),
            collectionID: collectionID,
            name: "Éditions Test"
        )
        let series = BookSeries(
            id: UUID(),
            collectionID: collectionID,
            name: "Saga Test",
            totalBookCount: nil
        )
        let resolver = BookReferenceResolver(
            collectionID: collectionID,
            catalogSeries: [series],
            catalogPublishers: [publisher],
            catalogPeople: [],
            contributors: [],
            selectedSeries: nil,
            selectedPublisher: nil
        )

        #expect(resolver.resolvePublisher(named: "  editions   TEST ")?.id == publisher.id)
        #expect(resolver.resolveSeries(named: "  SAGA   test ")?.id == series.id)
    }

    @Test
    func matchesPersonByInitialsWhenTheBestMatchIsUnique() {
        let person = makePerson(givenName: "Ivan", middleName: "Ivanovich", familyName: "Petrov")
        let resolver = makeResolver(people: [person])

        #expect(resolver.existingCatalogPerson(named: "I. Petrov")?.id == person.id)
        #expect(resolver.resolvePerson(named: "I. Petrov")?.id == person.id)
    }

    @Test
    func doesNotChooseBetweenAmbiguousPersonMatches() {
        let ivan = makePerson(givenName: "Ivan", familyName: "Petrov")
        let igor = makePerson(givenName: "Igor", familyName: "Petrov")
        let resolver = makeResolver(people: [ivan, igor])

        #expect(resolver.existingCatalogPerson(named: "I. Petrov") == nil)
    }

    @Test
    func availablePeopleIncludeTransientContributorWithoutDuplicatingCatalogPerson() {
        let catalogPerson = makePerson(givenName: "Anna", familyName: "Smith")
        let transientPerson = makePerson(givenName: "John", familyName: "Doe")
        let resolver = BookReferenceResolver(
            collectionID: testCollectionID,
            catalogSeries: [],
            catalogPublishers: [],
            catalogPeople: [catalogPerson],
            contributors: [
                BookContributor(role: .author, order: 0, person: catalogPerson),
                BookContributor(role: .editor, order: 1, person: transientPerson)
            ],
            selectedSeries: nil,
            selectedPublisher: nil
        )

        #expect(Set(resolver.availablePeople.map(\.id)) == Set([catalogPerson.id, transientPerson.id]))
    }

    @Test
    func ignoresPeopleAndPublishersFromOtherCollectionsInPickers() {
        let localPerson = makePerson(givenName: "Local")
        let foreignPerson = Person(
            id: UUID(),
            collectionID: UUID(),
            givenName: "Foreign",
            birthYear: nil,
            deathYear: nil,
            biography: nil,
            birthPlace: nil,
            deathPlace: nil
        )
        let localPublisher = Publisher(
            id: UUID(),
            collectionID: testCollectionID,
            name: "Local Publisher"
        )
        let foreignPublisher = Publisher(
            id: UUID(),
            collectionID: UUID(),
            name: "Foreign Publisher"
        )
        let resolver = BookReferenceResolver(
            collectionID: testCollectionID,
            catalogSeries: [],
            catalogPublishers: [localPublisher, foreignPublisher],
            catalogPeople: [localPerson, foreignPerson],
            contributors: [],
            selectedSeries: nil,
            selectedPublisher: nil
        )

        #expect(resolver.availablePeople.map(\.id) == [localPerson.id])
        #expect(resolver.availablePublishers.map(\.id) == [localPublisher.id])
    }

    @Test
    func materializesPersonFromAnotherCollectionWithCanonicalIdentity() {
        let canonicalID = UUID()
        let sourcePhoto = MediaAsset(
            id: UUID(),
            kind: .photo,
            displayName: "Portrait",
            sortOrder: 0,
            mimeType: "image/jpeg",
            originalData: Data([1, 2, 3])
        )
        let source = Person(
            id: UUID(),
            canonicalID: canonicalID,
            collectionID: UUID(),
            givenName: "Max",
            familyName: "Frei",
            birthYear: 1965,
            deathYear: nil,
            biography: "Biography",
            birthPlace: "Odessa",
            deathPlace: nil,
            photos: [sourcePhoto]
        )
        let resolver = makeResolver(people: [source])

        let resolved = resolver.resolvePerson(named: "Max Frei")

        #expect(resolved?.id != source.id)
        #expect(resolved?.canonicalID == canonicalID)
        #expect(resolved?.collectionID == testCollectionID)
        #expect(resolved?.givenName == source.givenName)
        #expect(resolved?.familyName == source.familyName)
        #expect(resolved?.photos.first?.id != sourcePhoto.id)
        #expect(resolved?.photos.first?.originalData == sourcePhoto.originalData)

        guard let resolved else { return }
        let statusResolver = BookReferenceResolver(
            collectionID: testCollectionID,
            catalogSeries: [],
            catalogPublishers: [],
            catalogPeople: [source],
            contributors: [BookContributor(role: .author, order: 0, person: resolved)],
            selectedSeries: nil,
            selectedPublisher: nil
        )
        #expect(statusResolver.status(for: .author(0))?.systemImage == "checkmark.circle.fill")
    }

    @Test
    func materializesPublisherFromAnotherCollectionWithCanonicalIdentity() {
        let canonicalID = UUID()
        let sourceLogo = MediaAsset(
            id: UUID(),
            kind: .photo,
            displayName: "Logo",
            sortOrder: 0,
            mimeType: "image/png",
            originalData: Data([4, 5, 6])
        )
        let source = Publisher(
            id: UUID(),
            canonicalID: canonicalID,
            collectionID: UUID(),
            name: "Amphora",
            logo: sourceLogo
        )
        let resolver = BookReferenceResolver(
            collectionID: testCollectionID,
            catalogSeries: [],
            catalogPublishers: [source],
            catalogPeople: [],
            contributors: [],
            selectedSeries: nil,
            selectedPublisher: nil
        )

        let resolved = resolver.resolvePublisher(named: "amphora")

        #expect(resolved?.id != source.id)
        #expect(resolved?.canonicalID == canonicalID)
        #expect(resolved?.collectionID == testCollectionID)
        #expect(resolved?.name == source.name)
        #expect(resolved?.logo?.id != sourceLogo.id)
        #expect(resolved?.logo?.originalData == sourceLogo.originalData)

        guard let resolved else { return }
        let statusResolver = BookReferenceResolver(
            collectionID: testCollectionID,
            catalogSeries: [],
            catalogPublishers: [source],
            catalogPeople: [],
            contributors: [],
            selectedSeries: nil,
            selectedPublisher: resolved
        )
        #expect(statusResolver.status(for: .field(.publisher))?.systemImage == "checkmark.circle.fill")
    }

    private func makeResolver(people: [Person]) -> BookReferenceResolver {
        BookReferenceResolver(
            collectionID: testCollectionID,
            catalogSeries: [],
            catalogPublishers: [],
            catalogPeople: people,
            contributors: [],
            selectedSeries: nil,
            selectedPublisher: nil
        )
    }

    private func makePerson(
        givenName: String,
        middleName: String? = nil,
        familyName: String? = nil
    ) -> Person {
        Person(
            id: UUID(),
            collectionID: testCollectionID,
            givenName: givenName,
            familyName: familyName,
            middleName: middleName,
            birthYear: nil,
            deathYear: nil,
            biography: nil,
            birthPlace: nil,
            deathPlace: nil
        )
    }
}
