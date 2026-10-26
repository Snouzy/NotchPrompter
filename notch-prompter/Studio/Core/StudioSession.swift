// Séance de tournage : un passage à la fois, décompte, défilement, essais (« Recommencer »), un fichier par passage,
// envoi au studio à la fin du passage. La caméra et le réseau passent par deux protocoles pour être testés sans rien lancer.
import Foundation
import Combine

/// La caméra : un fichier par passage. `elapsed` est le temps écoulé dans le fichier en cours.
protocol StudioRecorder: AnyObject {
    var elapsed: TimeInterval { get }
    func prepare() async throws
    func start(to url: URL) throws
    func stop() async throws -> URL
    func shutdown()
}

/// Le studio vidéo.
protocol StudioAPI {
    func fetch(_ link: StudioLink) async throws -> PrompterPayload
    func upload(file: URL, to url: URL, progress: @escaping @Sendable (Double) -> Void) async throws
}

struct StudioError: LocalizedError, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Envoi d'une prise au studio, affiché dans la fenêtre jusqu'à la fin de la séance.
struct UploadState: Identifiable, Equatable {
    enum Status: Equatable { case sending(Double), sent, failed(String) }
    let id: UUID
    let item: String
    let passageNumber: Int
    let file: URL
    var status: Status
}

@MainActor
final class StudioSession: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case ready              // le texte est là, on ne filme pas
        case countdown(Int)     // 3, 2, 1 avant chaque essai
        case reading            // le texte défile, l'essai est en cours
        case paused             // défilement figé, la caméra tourne toujours
        case finished           // tous les passages ont une prise envoyée ou en cours d'envoi
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var link: StudioLink?
    @Published private(set) var payload: PrompterPayload?
    @Published private(set) var index = 0
    @Published private(set) var isRecording = false
    @Published private(set) var attempts: [Attempt] = []
    @Published private(set) var uploads: [UploadState] = []
    @Published private(set) var scrollBase: Double = 0
    @Published private(set) var scrollStart: Date?
    /// Vitesse en points par seconde. Le changement garde la position actuelle (calculée avec l'ancienne vitesse).
    @Published var speed: Double {
        willSet { rebase() }
        didSet { defaults.set(speed, forKey: Keys.speed) }
    }
    @Published var fontSize: Double { didSet { defaults.set(fontSize, forKey: Keys.fontSize) } }

    var active: Bool { phase != .idle }
    var passages: [Passage] { payload?.passages ?? [] }
    var current: Passage? { passages.indices.contains(index) ? passages[index] : nil }
    var hasNext: Bool { index + 1 < passages.count }
    var hasPrevious: Bool { index > 0 }
    /// Nombre de passages dont une prise a été envoyée pendant cette séance.
    var sentCount: Int { Set(uploads.filter { $0.status == .sent }.map(\.item)).count }

    private let api: StudioAPI
    private let recorder: StudioRecorder
    private let folder: URL
    private let discard: (URL) -> Void
    private let now: () -> Date
    private let defaults: UserDefaults
    private var attemptStart: Double?
    private var countdownTask: Task<Void, Never>?
    private var uploadTasks: [Task<Void, Never>] = []
    let countdownSeconds: Int
    let countdownStep: Duration

    private enum Keys {
        static let speed = "StudioSpeed"
        static let fontSize = "StudioFontSize"
    }

    init(api: StudioAPI, recorder: StudioRecorder, folder: URL, defaults: UserDefaults = .standard,
         countdownSeconds: Int = 3, countdownStep: Duration = .seconds(1),
         now: @escaping () -> Date = Date.init, discard: @escaping (URL) -> Void = StudioSession.moveToTrash) {
        self.api = api
        self.recorder = recorder
        self.folder = folder
        self.defaults = defaults
        self.countdownSeconds = countdownSeconds
        self.countdownStep = countdownStep
        self.now = now
        self.discard = discard
        let s = defaults.double(forKey: Keys.speed), f = defaults.double(forKey: Keys.fontSize)
        speed = s > 0 ? s : 28
        fontSize = f > 0 ? f : 22
    }

    /// Le fichier part à la corbeille seulement après un envoi réussi : le studio en a une copie, et on peut le récupérer.
    nonisolated static func moveToTrash(_ url: URL) {
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    // MARK: Ouverture

    func open(_ link: StudioLink) async {
        if isRecording { await finishPassage() }
        cancelCountdown()
        self.link = link
        payload = nil
        index = 0
        attempts = []
        resetScroll()
        phase = .loading
        do {
            let p = try await api.fetch(link)
            guard !p.passages.isEmpty else {
                phase = .failed("Aucun passage à tourner dans « \(p.title) ». Marque un passage Face cam dans le studio.")
                return
            }
            payload = p
            phase = .ready
            try? await recorder.prepare()
        } catch {
            phase = .failed("Le studio ne répond pas (\(link.server.host ?? "")). Lance-le puis clique à nouveau sur « Lire au prompteur ».")
        }
    }

    /// Fin de séance : le passage filmé part au studio, la caméra s'éteint, la fenêtre revient au prompteur normal.
    func close() async {
        if isRecording { await finishPassage() }
        cancelCountdown()
        recorder.shutdown()
        phase = .idle
        payload = nil
        link = nil
    }

    // MARK: Enregistrement

    func toggleRecording() async {
        if isRecording { await stopRecording() } else { startRecording() }
    }

    func startRecording() {
        guard let current, let link, !isRecording else { return }
        do {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent(link.short), withIntermediateDirectories: true)
            let stamp = StudioSession.stampFormatter.string(from: now())
            let url = folder.appendingPathComponent(link.short).appendingPathComponent("\(current.item)-\(stamp).mov")
            try recorder.start(to: url)
            isRecording = true
            attempts = []
            beginCountdown()
        } catch {
            phase = .failed("La caméra ne démarre pas : \(error.localizedDescription)")
        }
    }

    func stopRecording() async {
        guard isRecording else { return }
        await finishPassage()
        phase = .ready
    }

    /// Nouvel essai sur le même passage : l'essai en cours se ferme, le texte repart du début après le décompte.
    func restart() {
        guard current != nil else { return }
        closeAttempt()
        resetScroll()
        if isRecording { beginCountdown() } else { phase = .ready }
    }

    func togglePause() {
        switch phase {
        case .reading:
            scrollBase = scrollOffset(at: now())
            scrollStart = nil
            phase = .paused
        case .paused:
            scrollStart = now()
            phase = .reading
        case .ready:
            // Lecture sans filmer, pour répéter.
            scrollStart = now()
            phase = .reading
        default:
            break
        }
    }

    // MARK: Navigation

    /// Passage suivant : si la caméra tourne, le passage en cours part au studio et le suivant démarre aussitôt.
    func next() async {
        guard hasNext else {
            if isRecording { await finishPassage(); phase = .finished }
            return
        }
        await move(by: 1)
    }

    func previous() async {
        guard hasPrevious else { return }
        await move(by: -1)
    }

    func select(_ i: Int) async {
        guard passages.indices.contains(i), i != index else { return }
        await move(by: i - index)
    }

    private func move(by delta: Int) async {
        let wasRecording = isRecording
        if wasRecording { await finishPassage() }
        cancelCountdown()
        index += delta
        attempts = []
        resetScroll()
        phase = .ready
        if wasRecording { startRecording() }
    }

    // MARK: Défilement

    /// Position du texte en points : figée en pause, sinon base + vitesse × temps écoulé.
    func scrollOffset(at date: Date) -> Double {
        guard let start = scrollStart else { return scrollBase }
        return scrollBase + max(0, date.timeIntervalSince(start)) * speed
    }

    func nudge(by points: Double) {
        scrollBase = max(0, scrollOffset(at: now()) + points)
        if scrollStart != nil { scrollStart = now() }
    }

    func faster() { speed = min(120, speed + 4) }
    func slower() { speed = max(4, speed - 4) }
    func larger() { fontSize = min(48, fontSize + 2) }
    func smaller() { fontSize = max(12, fontSize - 2) }

    private func rebase() {
        guard scrollStart != nil else { return }
        scrollBase = scrollOffset(at: now())
        scrollStart = now()
    }

    private func resetScroll() {
        scrollBase = 0
        scrollStart = nil
    }

    // MARK: Décompte et essais

    private func beginCountdown() {
        cancelCountdown()
        resetScroll()
        phase = .countdown(countdownSeconds)
        countdownTask = Task { [weak self, countdownSeconds, countdownStep] in
            for n in stride(from: countdownSeconds, to: 0, by: -1) {
                await MainActor.run { self?.phase = .countdown(n) }
                try? await Task.sleep(for: countdownStep)
                if Task.isCancelled { return }
            }
            await MainActor.run { self?.go() }
        }
    }

    private func go() {
        guard isRecording else { return }
        attemptStart = recorder.elapsed
        scrollStart = now()
        phase = .reading
    }

    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
    }

    private func closeAttempt() {
        guard let t0 = attemptStart else { return }
        attempts.append(Attempt(i: attempts.count, t0: t0, t1: max(t0, recorder.elapsed)))
        attemptStart = nil
    }

    /// Arrête le fichier du passage en cours et l'envoie au studio en arrière-plan.
    private func finishPassage() async {
        guard isRecording, let current, let link else { return }
        cancelCountdown()
        closeAttempt()
        let marks = attempts
        let number = index + 1
        isRecording = false
        resetScroll()
        do {
            let file = try await recorder.stop()
            send(file: file, item: current.item, passageNumber: number, attempts: marks, link: link)
        } catch {
            phase = .failed("La prise du passage \(number) n'a pas pu être enregistrée : \(error.localizedDescription)")
        }
    }

    private func send(file: URL, item: String, passageNumber: Int, attempts: [Attempt], link: StudioLink) {
        let id = UUID()
        uploads.append(UploadState(id: id, item: item, passageNumber: passageNumber, file: file, status: .sending(0)))
        let url = link.takeURL(item: item, fileName: file.lastPathComponent, attempts: attempts)
        let task = Task { [weak self, api, discard] in
            do {
                try await api.upload(file: file, to: url) { p in
                    Task { @MainActor in self?.setUpload(id, .sending(p)) }
                }
                await MainActor.run { self?.setUpload(id, .sent) }
                discard(file)
            } catch {
                await MainActor.run { self?.setUpload(id, .failed("Envoi raté, prise gardée dans \(file.deletingLastPathComponent().path)")) }
            }
        }
        uploadTasks.append(task)
    }

    private func setUpload(_ id: UUID, _ status: UploadState.Status) {
        guard let i = uploads.firstIndex(where: { $0.id == id }) else { return }
        // Une progression tardive ne doit pas effacer « envoyée ».
        if case .sending = status, uploads[i].status == .sent { return }
        uploads[i].status = status
    }

    /// Pour les tests : attend la fin des envois lancés.
    func waitForUploads() async {
        for t in uploadTasks { await t.value }
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()
}
