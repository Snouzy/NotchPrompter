// Relie le mode studio à l'app : lien notchprompter://, fenêtre sous l'encoche, raccourcis ⌥⌘ pendant la séance.
import AppKit
import Combine
import HotKey
import SwiftUI

@MainActor
final class StudioController: ObservableObject {
    let camera = CameraRecorder()
    let session: StudioSession
    private var window: NSWindow?
    private var hotKeys: [HotKey] = []
    private var cancellables: Set<AnyCancellable> = []
    /// Le prompteur normal se cache pendant la séance et revient après.
    private weak var prompter: PrompterViewModel?
    private var prompterWasVisible = false

    /// Les prises attendent ici le temps de l'envoi, puis partent à la corbeille (le studio garde sa copie).
    static let folder: URL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0].appendingPathComponent("NotchPrompter", isDirectory: true)

    init(prompter: PrompterViewModel) {
        self.prompter = prompter
        session = StudioSession(api: StudioClient(), recorder: camera, folder: StudioController.folder)
        session.$phase
            .map { $0 != .idle }
            .removeDuplicates()
            .sink { [weak self] active in active ? self?.didOpen() : self?.didClose() }
            .store(in: &cancellables)
    }

    func handle(_ url: URL) {
        guard let link = StudioLink(url: url) else { return }
        Task { await session.open(link) }
    }

    // MARK: Fenêtre

    private func didOpen() {
        if let prompter, window == nil {
            prompterWasVisible = prompter.isPrompterVisible
            prompter.isPrompterVisible = false
        }
        let w = window ?? makeWindow()
        window = w
        w.setFrame(frame(), display: true)
        w.orderFrontRegardless()
        registerHotKeys()
    }

    private func didClose() {
        hotKeys = []
        window?.orderOut(nil)
        window = nil
        if prompterWasVisible { prompter?.isPrompterVisible = true }
    }

    private func makeWindow() -> NSWindow {
        let view = StudioView(session: session, preview: AnyView(CameraPreview(session: camera.session)))
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 18, bottomTrailingRadius: 18, topTrailingRadius: 0))
        let hosting = NSHostingView(rootView: view)
        let w = NSPanel(contentRect: NSRect(origin: .zero, size: StudioView.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.level = .statusBar
        w.hasShadow = true
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Le texte ne doit pas apparaître dans un enregistrement d'écran ou un partage.
        w.sharingType = .none
        w.hidesOnDeactivate = false
        w.contentView = hosting
        return w
    }

    /// En haut au centre de l'écran qui a l'encoche (la caméra est là), sinon de l'écran principal.
    private func frame() -> NSRect {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        let s = StudioView.size
        return NSRect(x: screen.frame.midX - s.width / 2, y: screen.frame.maxY - s.height, width: s.width, height: s.height)
    }

    // MARK: Raccourcis

    /// Seulement pendant la séance, et toujours avec ⌥⌘ pour ne rien voler aux autres apps.
    private func registerHotKeys() {
        guard hotKeys.isEmpty else { return }
        let s = session
        let bindings: [(Key, () async -> Void)] = [
            (.r, { await s.toggleRecording() }),
            (.rightArrow, { await s.next() }),
            (.leftArrow, { await s.previous() }),
            (.return, { s.restart() }),
            (.p, { s.togglePause() }),
            (.upArrow, { s.faster() }),
            (.downArrow, { s.slower() }),
        ]
        hotKeys = bindings.map { key, action in
            let h = HotKey(key: key, modifiers: [.command, .option])
            h.keyDownHandler = { Task { @MainActor in await action() } }
            return h
        }
    }
}
