import SwiftUI
import AppKit

@main
struct NotchPrompterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(viewModel: appDelegate.viewModel)
                .onAppear(perform: {
                    NSApp.setActivationPolicy(.regular)
                })
                .onDisappear(perform: {
                    NSApp.setActivationPolicy(.accessory)
                })
        }

        MenuBarExtra {
            MenuContent(viewModel: appDelegate.viewModel, studio: appDelegate.studio, camera: appDelegate.studio.camera)
        } label: {
            let image: NSImage = {
                $0.size.height = 12
                $0.size.width = 12
                return $0
            }(NSImage(named: "MenuBarIcon")!)

            Image(nsImage: image)
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = PrompterViewModel()
    private var prompterWindow: PrompterWindow!
    @MainActor lazy var studio = StudioController(prompter: viewModel)

    // Le lien notchprompter:// du studio arrive par Apple Event, même quand l'app vient d'être lancée par ce lien.
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    @objc private func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let raw = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue, let url = URL(string: raw) else { return }
        MainActor.assumeIsolated { studio.handle(url) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        prompterWindow = PrompterWindow(viewModel: viewModel)
        NSApp.setActivationPolicy(.accessory)
    }
}

struct MenuContent: View {
    @ObservedObject var viewModel: PrompterViewModel
    @ObservedObject var studio: StudioController
    @ObservedObject var camera: CameraRecorder



    var body: some View {
        Button {
            viewModel.isPrompterVisible.toggle()
        } label: {
            Label(viewModel.isPrompterVisible ? "Hide Prompter" : "Show Prompter",
                  systemImage: viewModel.isPrompterVisible ? "eye.slash" : "eye")
        }
        .keyboardShortcut("h", modifiers: [.command, .option])

        Divider()

        Button("Play") {
               viewModel.play()
        }

        .disabled(viewModel.voiceActivation)
        .keyboardShortcut("p", modifiers: [.command, .option])

        Button {
            viewModel.reset()
        } label: {
            Label("Reset", systemImage: "arrow.counterclockwise")
        }


        Divider()

        // Mode studio : ouvert par « Lire au prompteur » dans le studio vidéo.
        Section("Mode studio") {
            if studio.session.active {
                Button("Fermer le mode studio") { Task { await studio.session.close() } }
            } else {
                Text("Ouvre-le depuis le studio : « Lire au prompteur »")
            }
            Picker("Caméra", selection: $camera.cameraID) {
                Text("Automatique (iPhone, sinon Mac)").tag(String?.none)
                ForEach(camera.cameras) { Text($0.name).tag(Optional($0.id)) }
            }
            Picker("Micro", selection: $camera.microphoneID) {
                Text("Par défaut du Mac").tag(String?.none)
                ForEach(camera.microphones) { Text($0.name).tag(Optional($0.id)) }
            }
            Button("Dossier des prises en attente") {
                try? FileManager.default.createDirectory(at: StudioController.folder, withIntermediateDirectories: true)
                NSWorkspace.shared.open(StudioController.folder)
            }
        }
        .onAppear { camera.refreshDevices() }

        Divider()

        SettingsLink {
            Label("Settings", systemImage: "gearshape")
        }

        .keyboardShortcut(",", modifiers: [.command])

        Divider()

        Button("Feedback") {
            if let url = URL(string: "mailto:jakub@jpomykala.com?subject=NotchPrompter%20feedback") {
                NSWorkspace.shared.open(url)
            }
        }

        Button("Project page") {
            if let url = URL(string: "https://notchprompter.com") {
                NSWorkspace.shared.open(url)
            }
        }

       Button("Help translate") {
           if let url = URL(string: "https://simplelocalize.io/suggestions/?id=f1f11f9305dc44a2872b6a154dea6edc") {
               NSWorkspace.shared.open(url)
           }
       }
    
        Divider()

        Button(role: .destructive) {
            NSApp.terminate(nil)
        } label: {
            Label("Exit", systemImage: "xmark.circle")
        }
        .keyboardShortcut("q", modifiers: [.command])
    }
}
