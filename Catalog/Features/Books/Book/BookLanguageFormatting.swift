import Foundation

enum BookLanguageFormatter {
    static func displayName(
        for code: String,
        locale: Locale = .current
    ) -> String {
        let name = locale.localizedString(forLanguageCode: code) ?? code.uppercased()
        guard let firstCharacter = name.first else { return name }

        return String(firstCharacter).uppercased(with: locale) + String(name.dropFirst())
    }
}
