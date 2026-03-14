import Combine
import Foundation
import SwiftUI

// MARK: - Types

enum GamePhase: Equatable {
    case menu
    case trackSelect
    case calibrateLow
    case calibrateHigh
    case countdown
    case playing
    case finished
    case freestyle
}

enum HitAccuracy: Equatable {
    case perfect, good, ok, miss, none

    var label: String {
        switch self {
        case .perfect: return "PERFECT!"
        case .good: return "Good!"
        case .ok: return "OK"
        case .miss: return "Miss"
        case .none: return ""
        }
    }

    var color: Color {
        switch self {
        case .perfect: return Color(red: 1.0, green: 0.85, blue: 0.0)
        case .good: return Color(red: 0.2, green: 0.9, blue: 0.4)
        case .ok: return Color(red: 0.6, green: 0.6, blue: 0.7)
        case .miss: return Color(red: 1.0, green: 0.3, blue: 0.3)
        case .none: return .clear
        }
    }
}

struct AccuracyPopup: Identifiable {
    let id = UUID()
    let accuracy: HitAccuracy
    let normalizedY: Double
    let birthTime: Double
}

struct Calibration: Codable {
    var minAngle: Double = 80.0
    var maxAngle: Double = 130.0
    var isCalibrated: Bool = false
}

// MARK: - Game State

final class GameState: ObservableObject {
    // Phase
    @Published var phase: GamePhase = .menu
    @Published var countdown: Int = 3

    // Song selection
    @Published var songs: [SongEntry] = []
    @Published var selectedSongIndex: Int = 0
    @Published var midiTracks: [(info: MIDITrackInfo, notes: [GameNote])] = []
    @Published var selectedTrackIndex: Int = 0
    @Published var trackName: String = ""

    // Core
    @Published var currentTime: Double = 0.0
    @Published var score: Int = 0
    @Published var combo: Int = 0
    @Published var maxCombo: Int = 0
    @Published var currentAccuracy: HitAccuracy = .none

    // Input
    @Published var currentAngle: Double = 105.0
    @Published var currentFrequency: Double = 261.6
    @Published var isBlowing: Bool = false

    // Popups
    @Published var popups: [AccuracyPopup] = []

    // Calibration
    @Published var calibration = Calibration() {
        didSet { saveCalibration() }
    }

    // Notes
    var notes: [GameNote] = []
    var minFrequency: Double = 130.0
    var maxFrequency: Double = 523.0

    // Per-note results
    private(set) var noteResults: [UUID: HitAccuracy] = [:]
    private var lastPopupTime: Double = -1.0

    // Angle smoothing
    private var smoothedAngle: Double = 105.0

    // Timing
    private var countdownStartTime: Date?
    private var playStartTime: Date?

    let lookAheadSeconds: Double = 4.5

    // Current MIDI URL for backing track
    var currentMIDIURL: URL?

    init() {
        loadCalibration()
    }

    // MARK: - Calibration Persistence

    private func saveCalibration() {
        if let data = try? JSONEncoder().encode(calibration) {
            UserDefaults.standard.set(data, forKey: "DisplayChamp_Calibration")
        }
    }

    private func loadCalibration() {
        if let data = UserDefaults.standard.data(forKey: "DisplayChamp_Calibration"),
           let cal = try? JSONDecoder().decode(Calibration.self, from: data) {
            calibration = cal
        }
    }

    // MARK: - Song Management

    func loadSongList(tracksDir: URL) {
        songs = []

        // Copy bundled tracks if not already present
        MIDILoader.copyBundledTracks(to: tracksDir)

        // Scan for MIDI files
        let midiFiles = MIDILoader.scanTracks(in: tracksDir)
        for file in midiFiles {
            let name = file.deletingPathExtension().lastPathComponent
            songs.append(SongEntry(name: name, source: .midiFile(file)))
        }
    }

    var selectedSong: SongEntry? {
        guard selectedSongIndex >= 0 && selectedSongIndex < songs.count else { return nil }
        return songs[selectedSongIndex]
    }

    /// Select a song and determine if track selection is needed.
    func selectSong(at index: Int) {
        selectedSongIndex = index
        guard let song = selectedSong else { return }

        let url: URL
        switch song.source {
        case .midiFile(let u): url = u
        }

        if let tracks = MIDILoader.loadMIDITracks(from: url) {
            midiTracks = tracks
            currentMIDIURL = url
            if tracks.count == 1 {
                selectTrack(0)
            } else {
                selectedTrackIndex = 0
                phase = .trackSelect
            }
        } else {
            loadNotes([], trackName: song.name)
            currentMIDIURL = nil
            midiTracks = []
        }
    }

    func selectTrack(_ index: Int) {
        selectedTrackIndex = index
        guard index < midiTracks.count else { return }
        let track = midiTracks[index]
        loadNotes(track.notes, trackName: "\(selectedSong?.name ?? "MIDI") - \(track.info.name)")
    }

    // MARK: - Song Info

    var songDuration: Double {
        guard let last = notes.last else { return 1.0 }
        return last.time + last.duration
    }

    var progress: Double {
        guard songDuration > 0 else { return 0 }
        return min(1.0, max(0.0, currentTime / songDuration))
    }

    // MARK: - Stats

    var notesPerfect: Int { noteResults.values.filter { $0 == .perfect }.count }
    var notesGood: Int { noteResults.values.filter { $0 == .good }.count }
    var notesOK: Int { noteResults.values.filter { $0 == .ok }.count }
    var notesMissed: Int { max(0, notes.filter { $0.time + $0.duration < currentTime }.count - noteResults.count) }
    var notesTotal: Int { notes.count }

    var grade: String {
        let total = notes.count
        guard total > 0 else { return "?" }
        let perfectRatio = Double(notesPerfect) / Double(total)
        let hitRatio = Double(noteResults.count) / Double(total)
        if perfectRatio >= 0.85 { return "S" }
        if perfectRatio >= 0.65 { return "A" }
        if perfectRatio >= 0.45 { return "B" }
        if hitRatio >= 0.5 { return "C" }
        if hitRatio >= 0.25 { return "D" }
        return "F"
    }

    var gradeColor: Color {
        switch grade {
        case "S": return Color(red: 1.0, green: 0.85, blue: 0.0)
        case "A": return Color(red: 0.2, green: 0.9, blue: 0.4)
        case "B": return Color(red: 0.3, green: 0.6, blue: 1.0)
        case "C": return Color(red: 0.6, green: 0.6, blue: 0.7)
        case "D": return Color(red: 0.8, green: 0.5, blue: 0.2)
        default: return Color(red: 1.0, green: 0.3, blue: 0.3)
        }
    }

    // MARK: - Setup

    func loadNotes(_ newNotes: [GameNote], trackName: String) {
        self.notes = newNotes
        self.trackName = trackName
        recalculateRange()
        _uniquePitches = nil
    }

    private func recalculateRange() {
        guard !notes.isEmpty else { return }
        let freqs = notes.map { $0.frequency }
        minFrequency = freqs.min()! / 1.1
        maxFrequency = freqs.max()! * 1.1
    }

    func reset() {
        currentTime = 0.0
        score = 0
        combo = 0
        maxCombo = 0
        currentAccuracy = .none
        noteResults = [:]
        lastPopupTime = -1.0
        popups = []
        countdownStartTime = nil
        playStartTime = nil
    }

    // MARK: - Calibration

    func startCalibration() {
        phase = .calibrateLow
    }

    func recordCalibrationLow() {
        calibration.minAngle = currentAngle
        phase = .calibrateHigh
    }

    func recordCalibrationHigh() {
        calibration.maxAngle = max(currentAngle, calibration.minAngle + 5.0)
        calibration.isCalibrated = true
        phase = .menu
    }

    // MARK: - Game Flow

    func startCountdown() {
        reset()
        countdown = 3
        countdownStartTime = Date()
        phase = .countdown
    }

    func startPlaying() {
        phase = .playing
        playStartTime = Date()
    }

    // MARK: - Input

    func updateAngle(_ rawAngle: Double) {
        smoothedAngle += (rawAngle - smoothedAngle) * 0.35
        currentAngle = smoothedAngle

        let range = calibration.maxAngle - calibration.minAngle
        let normalizedAngle = range > 1.0
            ? max(0.0, min(1.0, (smoothedAngle - calibration.minAngle) / range))
            : 0.5

        let logMin = log2(minFrequency)
        let logMax = log2(maxFrequency)
        currentFrequency = pow(2.0, logMin + normalizedAngle * (logMax - logMin))
    }

    // MARK: - Update

    func update() {
        switch phase {
        case .countdown:
            guard let start = countdownStartTime else { return }
            let elapsed = Date().timeIntervalSince(start)
            countdown = max(0, 3 - Int(elapsed))
            // Scroll notes in during countdown (-3 → 0)
            currentTime = elapsed - 3.0
            if elapsed >= 3.0 {
                startPlaying()
            }

        case .playing:
            guard let start = playStartTime else { return }
            currentTime = Date().timeIntervalSince(start)

            if currentTime > songDuration + 1.5 {
                phase = .finished
                return
            }

            if isBlowing {
                checkScoring()
            } else {
                currentAccuracy = .none
            }

            popups.removeAll { currentTime - $0.birthTime > 1.0 }

        default:
            break
        }
    }

    private func checkScoring() {
        let activeNote = notes.first { note in
            currentTime >= note.time - 0.15 && currentTime <= note.time + note.duration + 0.15
        }

        guard let note = activeNote else {
            currentAccuracy = .none
            return
        }

        let ratio = abs(currentFrequency - note.frequency) / note.frequency
        let accuracy: HitAccuracy
        let points: Int

        if ratio < 0.03 {
            accuracy = .perfect; points = 100
        } else if ratio < 0.16 {
            accuracy = .good; points = 50
        } else if ratio < 0.30 {
            accuracy = .ok; points = 20
        } else {
            accuracy = .miss; points = 0
        }

        currentAccuracy = accuracy

        if accuracy != .miss {
            let existing = noteResults[note.id]
            if existing == nil {
                combo += 1
                maxCombo = max(maxCombo, combo)
                let multiplier = min(1.0 + Double(combo) / 10.0, 4.0)
                score += Int(Double(points) * multiplier)
                noteResults[note.id] = accuracy

                if currentTime - lastPopupTime > 0.2 {
                    popups.append(AccuracyPopup(
                        accuracy: accuracy,
                        normalizedY: normalizedPitch(for: note.frequency),
                        birthTime: currentTime
                    ))
                    lastPopupTime = currentTime
                }
            } else if existing != .perfect && accuracy == .perfect {
                noteResults[note.id] = accuracy
                score += 30
            }
        } else if noteResults[note.id] == nil {
            combo = 0
        }
    }

    // MARK: - Helpers

    var visibleNotes: [GameNote] {
        notes.filter { note in
            let noteEnd = note.time + note.duration
            return noteEnd >= currentTime - 0.5 && note.time <= currentTime + lookAheadSeconds
        }
    }

    private var _uniquePitches: [Double]?
    var uniquePitches: [Double] {
        if let cached = _uniquePitches { return cached }
        let pitches = Array(Set(notes.map { $0.frequency })).sorted()
        _uniquePitches = pitches
        return pitches
    }

    func normalizedPitch(for frequency: Double) -> Double {
        let logMin = log2(minFrequency)
        let logMax = log2(maxFrequency)
        return max(0.0, min(1.0, (log2(frequency) - logMin) / (logMax - logMin)))
    }

    var cursorY: Double { normalizedPitch(for: currentFrequency) }

    var normalizedAngle: Double {
        let range = calibration.maxAngle - calibration.minAngle
        guard range > 1.0 else { return 0.5 }
        return max(0.0, min(1.0, (currentAngle - calibration.minAngle) / range))
    }

    func accuracyForNote(_ note: GameNote) -> HitAccuracy? {
        noteResults[note.id]
    }
}
