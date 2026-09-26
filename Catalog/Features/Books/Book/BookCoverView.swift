import SwiftUI

/// Renders the resolved visual cover of a book within the supplied maximum size.
struct BookCoverView: View {
    let cover: BookCoverContent
    let size: CGSize

    var body: some View {
        Group {
            switch cover {
            case let .image(asset):
                MediaPreviewImage(
                    identifier: asset.localIdentifier.isEmpty ? nil : asset.localIdentifier,
                    originalData: asset.originalData,
                    size: coverSize,
                    contentMode: .fit
                )

            case let .generated(generatedCover):
                generatedCoverView(generatedCover)
                    .frame(width: coverSize.width, height: coverSize.height)
            }
        }
        .frame(width: coverSize.width, height: coverSize.height)
    }

    private var coverSize: CGSize {
        let ratio = coverAspectRatio
        let widthAtMaximumHeight = size.height * ratio

        if widthAtMaximumHeight <= size.width {
            return CGSize(width: widthAtMaximumHeight, height: size.height)
        }

        return CGSize(width: size.width, height: size.width / ratio)
    }

    private var coverAspectRatio: CGFloat {
        switch cover {
        case let .image(asset):
            guard let width = asset.width,
                  let height = asset.height,
                  width > 0,
                  height > 0 else {
                return Self.generatedAspectRatio
            }
            return CGFloat(width) / CGFloat(height)

        case .generated:
            return Self.generatedAspectRatio
        }
    }

    private func generatedCoverView(_ generatedCover: BookGeneratedCover) -> some View {
        ZStack {
            LinearGradient(
                colors: BookCoverPalette.colors(for: generatedCover.bookID),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: generatedSpacing) {
                Spacer(minLength: 0)

                if !generatedCover.authorNames.isEmpty {
                    Text(generatedCover.authorNames.joined(separator: ", "))
                        .font(.system(size: authorFontSize, weight: .medium))
                        .foregroundStyle(.white.opacity(0.84))
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                }

                Text(generatedCover.title)
                    .font(.system(size: titleFontSize, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(4)
                    .minimumScaleFactor(0.68)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(generatedPadding)
        }
    }

    private var generatedPadding: CGFloat {
        min(max(coverSize.width * 0.09, 10), 22)
    }

    private var generatedSpacing: CGFloat {
        min(max(coverSize.width * 0.04, 6), 12)
    }

    private var titleFontSize: CGFloat {
        min(max(coverSize.width * 0.105, 13), 30)
    }

    private var authorFontSize: CGFloat {
        min(max(coverSize.width * 0.06, 10), 16)
    }

    private static let generatedAspectRatio: CGFloat = 2.0 / 3.0
}

/// Fills a card slot with a soft background derived from the resolved cover.
struct BookCoverBackdropView: View {
    let cover: BookCoverContent
    let size: CGSize

    var body: some View {
        Group {
            switch cover {
            case let .image(asset):
                MediaPreviewImage(
                    identifier: asset.localIdentifier.isEmpty ? nil : asset.localIdentifier,
                    originalData: asset.originalData,
                    size: size,
                    contentMode: .fill
                )
                .scaleEffect(1.08)
                .blur(radius: blurRadius)

            case let .generated(generatedCover):
                LinearGradient(
                    colors: BookCoverPalette.colors(for: generatedCover.bookID),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay {
            LinearGradient(
                colors: [
                    CatalogMediaContrast.scrimWeak,
                    CatalogMediaContrast.scrimMedium
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipped()
    }

    private var blurRadius: CGFloat {
        min(max(min(size.width, size.height) * 0.06, 8), 18)
    }
}

private enum BookCoverPalette {
    static func colors(for bookID: UUID) -> [Color] {
        let palettes: [[Color]] = [
            [
                Color(red: 0.30, green: 0.18, blue: 0.13),
                Color(red: 0.63, green: 0.39, blue: 0.24)
            ],
            [
                Color(red: 0.17, green: 0.29, blue: 0.25),
                Color(red: 0.31, green: 0.52, blue: 0.43)
            ],
            [
                Color(red: 0.35, green: 0.16, blue: 0.19),
                Color(red: 0.62, green: 0.31, blue: 0.35)
            ],
            [
                Color(red: 0.19, green: 0.23, blue: 0.34),
                Color(red: 0.37, green: 0.45, blue: 0.62)
            ],
            [
                Color(red: 0.28, green: 0.28, blue: 0.16),
                Color(red: 0.53, green: 0.50, blue: 0.28)
            ],
            [
                Color(red: 0.16, green: 0.27, blue: 0.31),
                Color(red: 0.30, green: 0.49, blue: 0.55)
            ]
        ]

        let index = bookID.uuidString.utf8.reduce(0) { partialResult, byte in
            (partialResult * 31 + Int(byte)) % palettes.count
        }
        return palettes[index]
    }
}
