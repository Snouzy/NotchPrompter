// Appels au studio vidéo : lecture des passages et envoi des prises (le corps est la vidéo, envoyée depuis le fichier).
import Foundation

final class StudioClient: NSObject, StudioAPI, URLSessionTaskDelegate {
    private let session: URLSession

    init(configuration: URLSessionConfiguration = .default) {
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60 * 60
        session = URLSession(configuration: configuration)
    }

    func fetch(_ link: StudioLink) async throws -> PrompterPayload {
        let (data, response) = try await session.data(from: link.prompterURL)
        try StudioClient.check(response, data)
        return try JSONDecoder().decode(PrompterPayload.self, from: data)
    }

    func upload(file: URL, to url: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(file.pathExtension.lowercased() == "mp4" ? "video/mp4" : "video/quicktime", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.upload(for: request, fromFile: file, delegate: ProgressDelegate(progress))
        try StudioClient.check(response, data)
        progress(1)
    }

    static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw StudioError("Réponse inattendue du studio") }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw StudioError(message ?? "Le studio a répondu \(http.statusCode)")
        }
    }

    private final class ProgressDelegate: NSObject, URLSessionTaskDelegate {
        let progress: @Sendable (Double) -> Void
        init(_ progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }
        func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
            guard totalBytesExpectedToSend > 0 else { return }
            progress(min(0.99, Double(totalBytesSent) / Double(totalBytesExpectedToSend)))
        }
    }
}
