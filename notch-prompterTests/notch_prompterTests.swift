// Tests du mode studio, sans app hôte : fausse caméra, faux studio, rendu de la fenêtre hors écran.
import AppKit
import Foundation
import SwiftUI
import Testing

// MARK: Doublures

final class FakeRecorder: StudioRecorder {
    var elapsed: TimeInterval = 0
    var started: [URL] = []
    var stopped = 0
    var current: URL?
    var shut = false
    func prepare() async throws {}
    func start(to url: URL) throws {
        try Data("video".utf8).write(to: url)
        started.append(url); current = url; elapsed = 0
    }
    func stop() async throws -> URL {
        stopped += 1
        defer { current = nil }
        return current!
    }
    func shutdown() { shut = true }
}

final class FakeAPI: StudioAPI, @unchecked Sendable {
    var payload: PrompterPayload
    var fail = false
    var uploads: [(file: URL, url: URL)] = []
    init(_ payload: PrompterPayload) { self.payload = payload }
    func fetch(_ link: StudioLink) async throws -> PrompterPayload { payload }
    func upload(file: URL, to url: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        progress(0.5)
        if fail { throw StudioError("hors ligne") }
        uploads.append((file, url))
        progress(1)
    }
}

let threePassages = PrompterPayload(short: "rust-1", title: "Rust · pilote", passages: [
    Passage(item: "iAll", from: nil, to: nil, global: true, takes: 0, text: "Salut, aujourd'hui je vous montre Rust."),
    Passage(item: "iA", from: 1, to: 4.9, global: false, takes: 0, text: "je vous montre rust"),
    Passage(item: "iB", from: 12.5, to: 15, global: false, takes: 1, text: "et c'est tout"),
])

let link = StudioLink(server: URL(string: "http://127.0.0.1:8770")!, short: "rust-1", items: ["iAll", "iA", "iB"])

func tempFolder() -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("np-tests-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

@MainActor
func makeSession(_ api: FakeAPI, _ rec: FakeRecorder, discarded: @escaping (URL) -> Void = { _ in }, now: @escaping () -> Date = Date.init) -> StudioSession {
    let defaults = UserDefaults(suiteName: "np-tests-\(UUID().uuidString)")!
    return StudioSession(api: api, recorder: rec, folder: tempFolder(), defaults: defaults, countdownSeconds: 3, countdownStep: .milliseconds(2), now: now, discard: discarded)
}

@MainActor
func waitUntil(_ condition: @escaping () -> Bool) async {
    for _ in 0..<500 where !condition() { try? await Task.sleep(for: .milliseconds(2)) }
}

// MARK: Lien et API

struct LinkTests {
    @Test func parsesTheStudioLink() throws {
        let l = try #require(StudioLink(url: URL(string: "notchprompter://open?server=http://127.0.0.1:8770&short=john-law-pilote&items=i1,i2")!))
        #expect(l.server.absoluteString == "http://127.0.0.1:8770")
        #expect(l.short == "john-law-pilote")
        #expect(l.items == ["i1", "i2"])
        #expect(l.prompterURL.absoluteString == "http://127.0.0.1:8770/api/short/john-law-pilote/prompter?items=i1,i2")
        let all = try #require(StudioLink(url: URL(string: "notchprompter://open?server=http://pas-un-sou.localhost:8770&short=s1")!))
        #expect(all.items.isEmpty)
        #expect(all.prompterURL.absoluteString == "http://pas-un-sou.localhost:8770/api/short/s1/prompter")
    }

    @Test(arguments: [
        "notchprompter://open?server=https://evil.example.com&short=s1",   // les prises ne partent que vers le studio local
        "notchprompter://open?server=file:///etc&short=s1",
        "notchprompter://open?server=http://127.0.0.1:8770&short=../../x",
        "notchprompter://open?server=http://127.0.0.1:8770",
        "notchprompter://delete?server=http://127.0.0.1:8770&short=s1",
        "https://open?server=http://127.0.0.1:8770&short=s1",
    ])
    func rejectsLinksOutsideTheLocalStudio(_ raw: String) {
        #expect(StudioLink(url: URL(string: raw)!) == nil)
    }

    @Test func buildsTheTakeUploadURL() throws {
        let url = link.takeURL(item: "iA", fileName: "iA-20261026-101500.mov", attempts: [Attempt(i: 0, t0: 0.5, t1: 3.25), Attempt(i: 1, t0: 3.8, t1: 9)])
        let q = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(url.path == "/api/short/rust-1/items/iA/takes")
        #expect(q.first { $0.name == "source" }?.value == "notchprompter")
        #expect(q.first { $0.name == "name" }?.value == "iA-20261026-101500.mov")
        #expect(q.first { $0.name == "passages" }?.value == #"[{"i":0,"t0":0.5,"t1":3.25},{"i":1,"t0":3.8,"t1":9}]"#)
        #expect(!link.takeURL(item: "iA", fileName: "a.mov", attempts: []).absoluteString.contains("passages"))
    }

    @Test func decodesTheStudioPayload() throws {
        let json = #"{"short":"s1","title":"John Law · pilote 1 min","passages":[{"item":"iAll","from":null,"to":null,"global":true,"takes":0,"text":"tout le texte"},{"item":"i2","from":61.5,"to":64.25,"global":false,"takes":2,"text":"un passage"}]}"#
        let p = try JSONDecoder().decode(PrompterPayload.self, from: Data(json.utf8))
        #expect(p.passages.count == 2)
        #expect(p.passages[0].rangeLabel == "Toute la vidéo")
        #expect(p.passages[1].rangeLabel == "01:01 → 01:04")
    }
}

// MARK: Séance

@MainActor
struct SessionTests {
    @Test func filmsEachPassageAndSendsItWithItsAttempts() async throws {
        let api = FakeAPI(threePassages), rec = FakeRecorder()
        var discarded: [URL] = []
        let s = makeSession(api, rec, discarded: { discarded.append($0) })
        await s.open(link)
        #expect(s.phase == .ready)
        #expect(s.current?.item == "iAll")

        s.startRecording()
        #expect(s.isRecording)
        #expect(s.phase == .countdown(3))
        await waitUntil { s.phase == .reading }
        #expect(s.phase == .reading)

        // Il bute : Recommencer ferme l'essai 0 et relance le décompte, la caméra continue.
        rec.elapsed = 4.2
        s.restart()
        #expect(s.attempts == [Attempt(i: 0, t0: 0, t1: 4.2)])
        await waitUntil { s.phase == .reading }
        rec.elapsed = 12

        // Suivant : la prise du passage 1 part au studio, le passage 2 démarre aussitôt dans un nouveau fichier.
        await s.next()
        #expect(s.current?.item == "iA")
        #expect(s.isRecording)
        #expect(rec.started.count == 2)
        await s.waitForUploads()
        let first = try #require(api.uploads.first)
        #expect(first.url.path == "/api/short/rust-1/items/iAll/takes")
        let passages = URLComponents(url: first.url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "passages" }?.value
        #expect(passages == #"[{"i":0,"t0":0,"t1":4.2},{"i":1,"t0":4.2,"t1":12}]"#)
        #expect(discarded == [first.file], "le fichier ne part à la corbeille qu'après l'envoi")

        await waitUntil { s.phase == .reading }
        await s.next()
        #expect(s.current?.item == "iB")
        await waitUntil { s.phase == .reading }
        await s.next()   // dernier passage : Terminer
        #expect(s.phase == .finished)
        #expect(!s.isRecording)
        await s.waitForUploads()
        #expect(api.uploads.map { $0.url.pathComponents[5] } == ["iAll", "iA", "iB"])
        #expect(s.sentCount == 3)

        await s.close()
        #expect(s.phase == .idle)
        #expect(rec.shut)
    }

    @Test func aFailedUploadKeepsTheFile() async throws {
        let api = FakeAPI(threePassages), rec = FakeRecorder()
        api.fail = true
        var discarded: [URL] = []
        let s = makeSession(api, rec, discarded: { discarded.append($0) })
        await s.open(link)
        s.startRecording()
        await waitUntil { s.phase == .reading }
        await s.stopRecording()
        #expect(s.phase == .ready)
        await s.waitForUploads()
        #expect(discarded.isEmpty)
        guard case .failed(let m) = s.uploads.last?.status else { Issue.record("envoi pas marqué raté"); return }
        #expect(m.contains("prise gardée"))
        #expect(FileManager.default.fileExists(atPath: rec.started[0].path))
    }

    @Test func closingWhileFilmingSendsTheTake() async {
        let api = FakeAPI(threePassages), rec = FakeRecorder()
        let s = makeSession(api, rec)
        await s.open(link)
        s.startRecording()
        await waitUntil { s.phase == .reading }
        await s.close()
        await s.waitForUploads()
        #expect(api.uploads.count == 1)
        #expect(s.phase == .idle)
    }

    @Test func noPassageExplainsWhatToDo() async {
        let s = makeSession(FakeAPI(PrompterPayload(short: "s1", title: "John Law", passages: [])), FakeRecorder())
        await s.open(link)
        guard case .failed(let m) = s.phase else { Issue.record("pas d'erreur"); return }
        #expect(m.contains("Marque un passage Face cam"))
    }

    @Test func scrollingPausesAndKeepsItsPlaceWhenTheSpeedChanges() async {
        var clock = Date(timeIntervalSince1970: 1000)
        let s = makeSession(FakeAPI(threePassages), FakeRecorder(), now: { clock })
        await s.open(link)
        s.speed = 20
        s.togglePause()          // répétition sans filmer : le texte défile
        #expect(s.phase == .reading)
        clock += 2
        #expect(s.scrollOffset(at: clock) == 40)
        s.speed = 40             // pas de saut : 40 points gardés, puis 40 pt/s
        #expect(s.scrollOffset(at: clock) == 40)
        clock += 1
        #expect(s.scrollOffset(at: clock) == 80)
        s.togglePause()
        clock += 5
        #expect(s.scrollOffset(at: clock) == 80)
        s.restart()
        #expect(s.scrollOffset(at: clock) == 0)
    }

    @Test func navigatingWithoutFilmingDoesNotRecord() async {
        let api = FakeAPI(threePassages), rec = FakeRecorder()
        let s = makeSession(api, rec)
        await s.open(link)
        await s.next()
        await s.next()
        #expect(s.index == 2)
        await s.next()
        #expect(s.index == 2)
        #expect(s.phase == .ready)
        await s.previous()
        #expect(s.index == 1)
        #expect(rec.started.isEmpty && api.uploads.isEmpty)
    }
}

// MARK: Rendu hors écran (fenêtre invisible, jamais affichée)

@MainActor
struct RenderTests {
    /// Dessine la vue dans une NSWindow jamais montrée et renvoie un PNG.
    func render(_ view: some View) throws -> Data {
        let size = StudioView.size
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    func save(_ data: Data, _ name: String) throws {
        let dir = ProcessInfo.processInfo.environment["RENDER_DIR"].map(URL.init(fileURLWithPath:)) ?? FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: dir.appendingPathComponent("\(name).png"))
    }

    @Test func rendersEachState() async throws {
        let api = FakeAPI(threePassages), rec = FakeRecorder()
        let clock = Date(timeIntervalSince1970: 1000)
        let s = makeSession(api, rec, now: { clock })
        let fake = AnyView(LinearGradient(colors: [.gray, .black], startPoint: .top, endPoint: .bottom))
        let view = StudioView(session: s, preview: fake, frozenDate: clock)

        await s.open(link)
        try save(try render(view), "1-pret")

        s.startRecording()
        try save(try render(view), "2-decompte")

        await waitUntil { s.phase == .reading }
        rec.elapsed = 5
        await s.next()
        await s.waitForUploads()
        await waitUntil { s.phase == .reading }
        try save(try render(view), "3-lecture-envoyee")

        await s.next(); await waitUntil { s.phase == .reading }
        await s.next()
        await s.waitForUploads()
        try save(try render(view), "4-termine")

        let empty = makeSession(FakeAPI(PrompterPayload(short: "s", title: "John Law", passages: [])), FakeRecorder())
        await empty.open(link)
        let png = try render(StudioView(session: empty, preview: fake, frozenDate: clock))
        try save(png, "5-aucun-passage")
        #expect(png.count > 5000)
    }
}

// MARK: Bout à bout avec un vrai serveur du studio (lancé par le script de test, projet temporaire)

struct EndToEndTests {
    static let env = ProcessInfo.processInfo.environment

    @Test(.enabled(if: env["STUDIO_E2E_URL"] != nil))
    func fetchesPassagesAndUploadsARealTake() async throws {
        let server = try #require(URL(string: Self.env["STUDIO_E2E_URL"]!))
        let short = try #require(Self.env["STUDIO_E2E_SHORT"])
        let movie = URL(fileURLWithPath: try #require(Self.env["STUDIO_E2E_MOVIE"]))
        let client = StudioClient()
        let link = StudioLink(server: server, short: short)
        let payload = try await client.fetch(link)
        let passage = try #require(payload.passages.first)
        #expect(passage.text == "je vous montre rust")
        let progress = ProgressBox()
        try await client.upload(file: movie, to: link.takeURL(item: passage.item, fileName: "prompteur.mov", attempts: [Attempt(i: 0, t0: 0.2, t1: 0.9)])) { progress.add($0) }
        #expect(progress.last == 1)
        await #expect(throws: StudioError.self) {
            try await client.upload(file: movie, to: link.takeURL(item: "inconnu", fileName: "x.mov", attempts: []), progress: { _ in })
        }
    }
}

final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []
    func add(_ v: Double) { lock.lock(); values.append(v); lock.unlock() }
    var last: Double? { lock.lock(); defer { lock.unlock() }; return values.last }
}
