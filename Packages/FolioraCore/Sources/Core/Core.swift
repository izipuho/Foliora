public enum Core {}

public enum FileNameSanitizer {
    public static func safeBaseName(_ value: String) -> String {
        let cleaned = String(value
            .lowercased()
            .map { $0 == " " ? "-" : $0 }
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        return cleaned.isEmpty ? "file" : cleaned
    }
}
