@preconcurrency import CoreNFC
import Foundation

extension NFCNDEFReaderSession: @unchecked @retroactive Sendable {}
extension NFCNDEFMessage: @unchecked @retroactive Sendable {}
extension NFCNDEFPayload: @unchecked @retroactive Sendable {}

enum NFCServiceError: LocalizedError, Equatable {
    case unavailable
    case userCanceled
    case invalidTag
    case nonWritableTag
    case unknownTag
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "NFC is not available on this device."
        case .userCanceled:
            return "Canceled"
        case .invalidTag:
            return "Invalid tag"
        case .nonWritableTag:
            return "Tag is not writable"
        case .unknownTag:
            return "Unknown tag"
        case .writeFailed:
            return "Failed to write NFC tag"
        }
    }
}

struct NFCWritePreparation {
    let currentTagURL: URL?
    let write: () -> Void
    let cancel: () -> Void
}

private struct SendableNFCTag: @unchecked Sendable {
    let value: any NFCNDEFTag
}

private struct SendablePreparationCallback: @unchecked Sendable {
    let value: (Result<NFCWritePreparation, NFCServiceError>) -> Void
}

final class NFCService: NSObject, @unchecked Sendable {
    private enum Mode {
        case read((Result<URL, NFCServiceError>) -> Void)
        case write(
            url: URL,
            (Result<NFCWritePreparation, NFCServiceError>) -> Void,
            (Result<Void, NFCServiceError>) -> Void
        )
    }

    private var session: NFCNDEFReaderSession?
    private var mode: Mode?

    func scan(completion: @escaping (Result<URL, NFCServiceError>) -> Void) {
        guard NFCNDEFReaderSession.readingAvailable else {
            completion(.failure(.unavailable))
            return
        }

        mode = .read(completion)
        let session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: true)
        session.alertMessage = "Hold near an NFC tag."
        self.session = session
        session.begin()
    }

    func prepareWrite(
        url: URL,
        preparation: @escaping (Result<NFCWritePreparation, NFCServiceError>) -> Void,
        completion: @escaping (Result<Void, NFCServiceError>) -> Void
    ) {
        guard NFCNDEFReaderSession.readingAvailable else {
            preparation(.failure(.unavailable))
            return
        }

        mode = .write(url: url, preparation, completion)
        let session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        session.alertMessage = "Hold near the NFC tag to write."
        self.session = session
        session.begin()
    }

    private func completeRead(_ result: Result<URL, NFCServiceError>) {
        guard case .read(let completion) = mode else { return }
        completion(result)
        mode = nil
        session = nil
    }

    private func completeWrite(_ result: Result<Void, NFCServiceError>) {
        guard case .write(_, _, let completion) = mode else { return }
        completion(result)
        mode = nil
        session = nil
    }

    private func url(from message: NFCNDEFMessage) -> URL? {
        message.records.lazy.compactMap { record in
            record.wellKnownTypeURIPayload()
        }.first
    }

    private func message(for url: URL) -> NFCNDEFMessage? {
        NFCNDEFPayload.wellKnownTypeURIPayload(url: url).map { NFCNDEFMessage(records: [$0]) }
    }
}

extension NFCService: NFCNDEFReaderSessionDelegate {
    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: any Error) {
        let nsError = error as NSError
        let serviceError: NFCServiceError = nsError.code == NFCReaderError.readerSessionInvalidationErrorUserCanceled.rawValue ? .userCanceled : .invalidTag

        switch mode {
        case .read:
            completeRead(.failure(serviceError))
        case .write:
            completeWrite(.failure(serviceError))
        case .none:
            break
        }
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        guard let url = messages.lazy.compactMap(url(from:)).first else {
            completeRead(.failure(.unknownTag))
            return
        }

        completeRead(.success(url))
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        guard case .write(let url, let preparation, _) = mode else { return }
        guard tags.count == 1, let tag = tags.first else {
            session.invalidate(errorMessage: NFCServiceError.invalidTag.localizedDescription)
            completeWrite(.failure(.invalidTag))
            return
        }

        let sendableTag = SendableNFCTag(value: tag)
        let sendablePreparation = SendablePreparationCallback(value: preparation)

        session.connect(to: sendableTag.value) { [service = self] error in
            guard error == nil else {
                session.invalidate(errorMessage: NFCServiceError.invalidTag.localizedDescription)
                service.completeWrite(.failure(.invalidTag))
                return
            }

            sendableTag.value.queryNDEFStatus { status, capacity, _ in
                guard status == .readWrite else {
                    session.invalidate(errorMessage: NFCServiceError.nonWritableTag.localizedDescription)
                    service.completeWrite(.failure(.nonWritableTag))
                    return
                }

                guard let message = service.message(for: url), message.length <= capacity else {
                    session.invalidate(errorMessage: NFCServiceError.invalidTag.localizedDescription)
                    service.completeWrite(.failure(.invalidTag))
                    return
                }

                sendableTag.value.readNDEF { existingMessage, _ in
                    let currentURL = existingMessage.flatMap(service.url(from:))
                    let preparationResult = NFCWritePreparation(
                        currentTagURL: currentURL,
                        write: {
                            sendableTag.value.writeNDEF(message) { error in
                                if error == nil {
                                    session.alertMessage = "NFC tag written."
                                    session.invalidate()
                                    service.completeWrite(.success(()))
                                } else {
                                    session.invalidate(errorMessage: NFCServiceError.writeFailed.localizedDescription)
                                    service.completeWrite(.failure(.writeFailed))
                                }
                            }
                        },
                        cancel: {
                            session.invalidate()
                            service.completeWrite(.failure(.userCanceled))
                        }
                    )
                    sendablePreparation.value(.success(preparationResult))
                }
            }
        }
    }
}
