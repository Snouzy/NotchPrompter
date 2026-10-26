// Fenêtre du mode studio, sous l'encoche : état du tournage, texte du passage qui défile, aperçu caméra et commandes.
import SwiftUI

struct StudioView: View {
    @ObservedObject var session: StudioSession
    var preview: AnyView = AnyView(Color.black)
    /// Pour le rendu hors écran des tests : une date fixe au lieu de l'horloge.
    var frozenDate: Date?

    static let size = CGSize(width: 600, height: 300)
    /// Hauteur cachée sous l'encoche.
    static let notchInset: CGFloat = 34

    @State private var textHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: StudioView.notchInset)
            header
                .padding(.horizontal, 18)
                .padding(.bottom, 6)
            reader
            controls
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(width: StudioView.size.width, height: StudioView.size.height)
        .background(Color.black)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    // MARK: En-tête

    private var header: some View {
        HStack(spacing: 8) {
            if session.isRecording {
                HStack(spacing: 5) {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                    Text("REC").font(.system(size: 11, weight: .bold))
                }
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(Color.red.opacity(0.22)))
            }
            (Text(session.payload?.title ?? "Mode studio").font(.system(size: 12, weight: .semibold))
             + Text(details).font(.system(size: 12)).foregroundColor(.white.opacity(0.6)))
                .lineLimit(1)
            Spacer(minLength: 4)
            uploadBadge
        }
    }

    /// « · Passage 2/3 · 00:01 → 00:04 · essai 2 » (l'essai seulement pendant qu'on filme).
    private var details: String {
        guard let p = session.current, session.phase != .finished else { return "" }
        var d = "  ·  Passage \(session.index + 1)/\(session.passages.count)"
        if !p.rangeLabel.isEmpty { d += "  ·  \(p.rangeLabel)" }
        if session.isRecording, !session.attempts.isEmpty { d += "  ·  essai \(session.attempts.count + 1)" }
        return d
    }

    @ViewBuilder private var uploadBadge: some View {
        if let last = session.uploads.last {
            switch last.status {
            case .sending(let p):
                Label("Envoi passage \(last.passageNumber) · \(Int(p * 100)) %", systemImage: "arrow.up.circle")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.75))
            case .sent:
                Label("\(session.sentCount) prise\(session.sentCount > 1 ? "s" : "") dans le studio", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11)).foregroundStyle(Color(red: 0.69, green: 0.88, blue: 0.09))
            case .failed:
                Label("Envoi raté", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundStyle(.orange)
                    .help(failureText(last))
            }
        }
    }

    private func failureText(_ u: UploadState) -> String {
        if case .failed(let m) = u.status { return m }
        return ""
    }

    // MARK: Texte

    @ViewBuilder private var reader: some View {
        switch session.phase {
        case .idle, .loading:
            message(icon: "arrow.down.circle", title: "Chargement des passages…", detail: session.link.map { "Studio \($0.server.host ?? "")" } ?? "")
        case .failed(let m):
            message(icon: "exclamationmark.triangle", title: "Impossible de continuer", detail: m,
                    action: ("Fermer", { await session.close() }))
        case .finished:
            message(icon: "checkmark.seal", title: "Tout est tourné",
                    detail: "\(session.uploads.count) prise\(session.uploads.count > 1 ? "s" : "") envoyée\(session.uploads.count > 1 ? "s" : "") au studio. Claude les montera quand tu appliqueras les retours.",
                    action: ("Fermer", { await session.close() }))
        default:
            scrollingText
        }
    }

    private func message(icon: String, title: String, detail: String, action: (String, () async -> Void)? = nil) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 22)).foregroundStyle(.white.opacity(0.7))
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center).lineLimit(3)
            if let action {
                Button { Task { await action.1() } } label: {
                    Text(action.0).font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14).frame(height: 26)
                        .background(Capsule().fill(Color.white.opacity(0.16)))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scrollingText: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1 / 60, paused: session.phase != .reading || frozenDate != nil)) { ctx in
                let raw = session.scrollOffset(at: frozenDate ?? ctx.date)
                let offset = min(raw, max(0, Double(textHeight) - 40))
                Text(session.current?.text ?? "")
                    .font(.system(size: session.fontSize, weight: .medium))
                    .lineSpacing(session.fontSize * 0.35)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: geo.size.width - 48)
                    .background(GeometryReader { g in Color.clear.preference(key: TextHeightKey.self, value: g.size.height) })
                    // Première ligne en haut, près de la caméra : les yeux restent sur l'objectif.
                    .offset(y: 8 - offset)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            }
            .clipped()
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.7), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay { countdownOverlay }
        }
        .onPreferenceChange(TextHeightKey.self) { textHeight = $0 }
    }

    @ViewBuilder private var countdownOverlay: some View {
        if case .countdown(let n) = session.phase {
            ZStack {
                Color.black.opacity(0.55)
                VStack(spacing: 2) {
                    Text("\(n)").font(.system(size: 56, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("Regarde l'objectif").font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    // MARK: Commandes

    private var controls: some View {
        HStack(spacing: 8) {
            preview
                .frame(width: 96, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(session.isRecording ? Color.red : Color.white.opacity(0.15), lineWidth: 1.5))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    iconButton("chevron.left", help: "Passage précédent (⌥⌘←)", disabled: !session.hasPrevious || !canControl) { await session.previous() }
                    recordButton
                    iconButton("arrow.counterclockwise", help: "Recommencer le passage (⌥⌘↩)", disabled: session.current == nil || !canControl) { session.restart() }
                    iconButton(session.phase == .reading ? "pause.fill" : "play.fill", help: "Pause ou reprise du défilement (⌥⌘P)", disabled: !canPause) { session.togglePause() }
                    nextButton
                    Spacer(minLength: 0)
                    iconButton("tortoise", help: "Plus lent (⌥⌘↓)", disabled: false) { session.slower() }
                    iconButton("hare", help: "Plus rapide (⌥⌘↑)", disabled: false) { session.faster() }
                    iconButton("xmark", help: "Fermer le mode studio (la prise en cours part au studio)", disabled: false) { await session.close() }
                }
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
        }
    }

    private var canControl: Bool {
        switch session.phase { case .ready, .countdown, .reading, .paused: return true; default: return false }
    }

    private var canPause: Bool {
        switch session.phase { case .ready, .reading, .paused: return true; default: return false }
    }

    private var hint: String {
        switch session.phase {
        case .ready: return session.isRecording ? "" : "Filmer lance un décompte de 3 s, puis le texte défile. ⌥⌘R au clavier."
        case .countdown: return "Prépare-toi, le texte part à la fin du décompte."
        case .reading: return session.hasNext ? "Tu butes ? Recommencer. C'est bon ? Suivant envoie la prise au studio." : "C'est bon ? Terminer envoie la prise au studio."
        case .paused: return "Défilement en pause, la caméra tourne toujours."
        default: return ""
        }
    }

    private var recordButton: some View {
        Button {
            Task { await session.toggleRecording() }
        } label: {
            Label(session.isRecording ? "Arrêter" : "Filmer", systemImage: session.isRecording ? "stop.fill" : "record.circle")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10).frame(height: 26)
                .background(Capsule().fill(session.isRecording ? Color.white.opacity(0.16) : Color.red))
        }
        .buttonStyle(.plain)
        .disabled(!canControl)
        .help("Filmer ou arrêter (⌥⌘R)")
    }

    private var nextButton: some View {
        let last = !session.hasNext
        return Button {
            Task { await session.next() }
        } label: {
            Label(last ? "Terminer" : "Suivant", systemImage: last ? "checkmark" : "chevron.right")
                .labelStyle(TrailingIconLabelStyle())
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10).frame(height: 26)
                .background(Capsule().fill(Color.white.opacity(0.16)))
        }
        .buttonStyle(.plain)
        .disabled(!canControl || (last && !session.isRecording))
        .help(last ? "Arrêter et envoyer la dernière prise (⌥⌘→)" : "Passage suivant : la prise part au studio (⌥⌘→)")
    }

    private func iconButton(_ name: String, help: String, disabled: Bool, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: name)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .help(help)
    }
}

private struct TextHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.title; configuration.icon }
    }
}
