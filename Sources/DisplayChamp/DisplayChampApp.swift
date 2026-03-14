import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }
}

@main
struct DisplayChampApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var gameState = GameState()
    private let sensor = LidAngleSensor()
    private let toneGenerator = ToneGenerator()
    private let backingPlayer = BackingTrackPlayer()

    var body: some Scene {
        WindowGroup {
            GameView(gameState: gameState, onOpenTracksFolder: openTracksFolder, onRefreshSongs: { loadSongList() })
                .onAppear {
                    loadSongList()
                    setupInputHandlers()
                    startGameLoop()
                }
                .onDisappear {
                    toneGenerator.stop()
                    backingPlayer.cleanup()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }

    private static var tracksDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("DisplayChamp/tracks")
    }

    private func loadSongList() {
        let tracksDir = Self.tracksDirectory
        try? FileManager.default.createDirectory(at: tracksDir, withIntermediateDirectories: true)
        gameState.loadSongList(tracksDir: tracksDir)
    }

    private func openTracksFolder() {
        let tracksDir = Self.tracksDirectory
        try? FileManager.default.createDirectory(at: tracksDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(tracksDir)
    }

    private func playSong() {
        gameState.selectSong(at: gameState.selectedSongIndex)
        if gameState.phase != .trackSelect {
            gameState.startCountdown()
        }
    }

    private func setupInputHandlers() {
        // Mouse/trackpad down
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            handlePress(isKeyboard: false)
            return event
        }

        // Mouse/trackpad up
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { event in
            handleRelease()
            return event
        }

        // Keyboard — return nil to consume the event and prevent system sounds
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Ignore key repeats entirely
            if event.isARepeat { return nil }

            switch event.keyCode {
            case 49: // Space
                handlePress(isKeyboard: true)
                return nil
            case 8: // C key
                if gameState.phase == .menu {
                    gameState.startCalibration()
                    return nil
                }
            case 34: // I key
                if gameState.phase == .menu {
                    openTracksFolder()
                    return nil
                }
            case 53: // Escape
                switch gameState.phase {
                case .playing:
                    gameState.phase = .menu
                    gameState.isBlowing = false
                    toneGenerator.noteOff()
                    backingPlayer.stop()
                case .freestyle:
                    gameState.phase = .menu
                    gameState.isBlowing = false
                    toneGenerator.noteOff()
                case .trackSelect, .calibrateLow, .calibrateHigh:
                    gameState.phase = .menu
                case .countdown:
                    gameState.phase = .menu
                    backingPlayer.stop()
                default:
                    break
                }
                return nil
            default:
                break
            }
            return event
        }

        NSEvent.addLocalMonitorForEvents(matching: .keyUp) { event in
            if event.keyCode == 49 { // Space
                handleRelease()
                return nil
            }
            return event
        }
    }

    private func handlePress(isKeyboard: Bool) {
        switch gameState.phase {
        case .menu:
            if isKeyboard {
                // Space starts the game from menu
                playSong()
            }
            // Mouse clicks: let SwiftUI buttons handle
        case .trackSelect:
            // Let SwiftUI buttons handle clicks
            break
        case .calibrateLow:
            gameState.recordCalibrationLow()
        case .calibrateHigh:
            gameState.recordCalibrationHigh()
        case .countdown:
            break
        case .playing, .freestyle:
            gameState.isBlowing = true
            toneGenerator.noteOn()
        case .finished:
            backingPlayer.stop()
            gameState.phase = .menu
        }
    }

    private func handleRelease() {
        if gameState.phase == .playing || gameState.phase == .freestyle {
            gameState.isBlowing = false
            toneGenerator.noteOff()
        }
    }

    private func startGameLoop() {
        var lastPhase: GamePhase = .menu

        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            // Read sensor
            if let angle = sensor.readAngle() {
                gameState.updateAngle(angle)
            }

            // Update audio pitch
            toneGenerator.setFrequency(gameState.currentFrequency)

            // Update game logic
            gameState.update()

            // Phase transition handling
            let currentPhase = gameState.phase
            if currentPhase != lastPhase {
                if currentPhase == .playing {
                    // Start backing track when gameplay begins
                    if let url = gameState.currentMIDIURL {
                        backingPlayer.prepare(midiURL: url, muteTrackIndex: gameState.selectedTrackIndex)
                        backingPlayer.start()
                    }
                } else if lastPhase == .playing {
                    // Stop backing track when leaving gameplay
                    backingPlayer.stop()
                    toneGenerator.noteOff()
                    gameState.isBlowing = false
                }
                lastPhase = currentPhase
            }
        }
    }
}
