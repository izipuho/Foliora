import Foundation

struct CloudKitConfiguration {
    let containerIdentifier: String

    static let containerIdentifier = "iCloud.com.izipuho.Foliora"

    static let `default` = CloudKitConfiguration(
        containerIdentifier: containerIdentifier
    )
}
