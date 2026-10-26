// Mode studio : le studio vidéo (video-studio) envoie les passages à dire face caméra, le prompteur les affiche un par un,
// filme chaque passage et renvoie la prise au studio avec les temps de chaque essai.
import Foundation

/// Lien ouvert par le bouton « Lire au prompteur » du studio :
/// notchprompter://open?server=http://127.0.0.1:8770&short=<id>&items=a,b
struct StudioLink: Equatable {
    let server: URL
    let short: String
    let items: [String]

    init(server: URL, short: String, items: [String] = []) {
        self.server = server
        self.short = short
        self.items = items
    }

    init?(url: URL) {
        guard url.scheme?.lowercased() == "notchprompter", url.host?.lowercased() == "open",
              let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        let value = { (name: String) in q.first { $0.name == name }?.value?.trimmingCharacters(in: .whitespaces) }
        // Seulement le studio local : le lien vient d'une page web, il ne doit pas pouvoir envoyer les prises ailleurs.
        guard let raw = value("server"), let server = URL(string: raw), ["http", "https"].contains(server.scheme ?? ""),
              let host = server.host, StudioLink.isLocal(host),
              let short = value("short"), StudioLink.isId(short) else { return nil }
        let items = (value("items") ?? "").split(separator: ",").map(String.init).filter(StudioLink.isId)
        self.init(server: server, short: short, items: items)
    }

    static func isLocal(_ host: String) -> Bool {
        let h = host.lowercased()
        return h == "127.0.0.1" || h == "localhost" || h == "::1" || h.hasSuffix(".localhost")
    }

    static func isId(_ s: String) -> Bool {
        !s.isEmpty && s.count <= 120 && s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }
    }

    /// GET /api/short/:id/prompter?items=…
    var prompterURL: URL {
        var c = URLComponents(url: server.appendingPathComponent("api/short/\(short)/prompter"), resolvingAgainstBaseURL: false)!
        if !items.isEmpty { c.queryItems = [URLQueryItem(name: "items", value: items.joined(separator: ","))] }
        return c.url!
    }

    /// POST /api/short/:id/items/:item/takes?name=…&source=notchprompter&passages=[…]
    func takeURL(item: String, fileName: String, attempts: [Attempt]) -> URL {
        var c = URLComponents(url: server.appendingPathComponent("api/short/\(short)/items/\(item)/takes"), resolvingAgainstBaseURL: false)!
        var q = [URLQueryItem(name: "name", value: fileName), URLQueryItem(name: "source", value: "notchprompter")]
        if !attempts.isEmpty, let data = try? JSONEncoder.sorted.encode(attempts), let json = String(data: data, encoding: .utf8) {
            q.append(URLQueryItem(name: "passages", value: json))
        }
        c.queryItems = q
        // « + » et « & » dans le JSON doivent rester littéraux côté serveur.
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return c.url!
    }
}

/// Réponse de GET /api/short/:id/prompter.
struct PrompterPayload: Codable, Equatable {
    let short: String
    let title: String
    let passages: [Passage]
}

struct Passage: Codable, Equatable, Identifiable {
    let item: String
    let from: Double?
    let to: Double?
    let global: Bool
    let takes: Int
    let text: String

    var id: String { item }

    /// « 00:01 → 00:04 » ou « Toute la vidéo ».
    var rangeLabel: String {
        if global { return "Toute la vidéo" }
        guard let from else { return "" }
        return to.map { "\(Passage.clock(from)) → \(Passage.clock($0))" } ?? Passage.clock(from)
    }

    static func clock(_ t: Double) -> String {
        let s = Int(t.rounded(.down))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

/// Un essai dans une prise : de « Go » (fin du décompte) à « Recommencer » ou à l'arrêt, en secondes depuis le début du fichier.
struct Attempt: Codable, Equatable {
    let i: Int
    let t0: Double
    let t1: Double
}

extension JSONEncoder {
    static let sorted: JSONEncoder = { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return e }()
}
