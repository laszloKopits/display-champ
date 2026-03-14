import AudioToolbox
import Foundation

// MARK: - Data Types

struct GameNote: Identifiable {
    let id = UUID()
    let time: Double
    let frequency: Double
    let duration: Double
    let midiNote: UInt8

    var noteName: String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = Int(midiNote) / 12 - 1
        return "\(names[Int(midiNote) % 12])\(octave)"
    }
}

struct MIDITrackInfo: Identifiable {
    let id: Int          // track index
    let noteCount: Int
    let lowestNote: UInt8
    let highestNote: UInt8
    var name: String
    var instrument: String?

    var rangeString: String {
        let low = GameNote(time: 0, frequency: 0, duration: 0, midiNote: lowestNote).noteName
        let high = GameNote(time: 0, frequency: 0, duration: 0, midiNote: highestNote).noteName
        return "\(low)-\(high)"
    }

    var displayName: String {
        if let inst = instrument, !inst.isEmpty {
            return "\(name) (\(inst))"
        }
        return name
    }
}

// General MIDI instrument names
private let gmInstrumentNames: [String] = [
    // Piano (0-7)
    "Acoustic Grand Piano", "Bright Acoustic Piano", "Electric Grand Piano", "Honky-tonk Piano",
    "Electric Piano 1", "Electric Piano 2", "Harpsichord", "Clavinet",
    // Chromatic Percussion (8-15)
    "Celesta", "Glockenspiel", "Music Box", "Vibraphone",
    "Marimba", "Xylophone", "Tubular Bells", "Dulcimer",
    // Organ (16-23)
    "Drawbar Organ", "Percussive Organ", "Rock Organ", "Church Organ",
    "Reed Organ", "Accordion", "Harmonica", "Tango Accordion",
    // Guitar (24-31)
    "Nylon Guitar", "Steel Guitar", "Jazz Guitar", "Clean Guitar",
    "Muted Guitar", "Overdriven Guitar", "Distortion Guitar", "Guitar Harmonics",
    // Bass (32-39)
    "Acoustic Bass", "Fingered Bass", "Picked Bass", "Fretless Bass",
    "Slap Bass 1", "Slap Bass 2", "Synth Bass 1", "Synth Bass 2",
    // Strings (40-47)
    "Violin", "Viola", "Cello", "Contrabass",
    "Tremolo Strings", "Pizzicato Strings", "Orchestral Harp", "Timpani",
    // Ensemble (48-55)
    "String Ensemble 1", "String Ensemble 2", "Synth Strings 1", "Synth Strings 2",
    "Choir Aahs", "Voice Oohs", "Synth Voice", "Orchestra Hit",
    // Brass (56-63)
    "Trumpet", "Trombone", "Tuba", "Muted Trumpet",
    "French Horn", "Brass Section", "Synth Brass 1", "Synth Brass 2",
    // Reed (64-71)
    "Soprano Sax", "Alto Sax", "Tenor Sax", "Baritone Sax",
    "Oboe", "English Horn", "Bassoon", "Clarinet",
    // Pipe (72-79)
    "Piccolo", "Flute", "Recorder", "Pan Flute",
    "Blown Bottle", "Shakuhachi", "Whistle", "Ocarina",
    // Synth Lead (80-87)
    "Lead 1 (Square)", "Lead 2 (Sawtooth)", "Lead 3 (Calliope)", "Lead 4 (Chiff)",
    "Lead 5 (Charang)", "Lead 6 (Voice)", "Lead 7 (Fifths)", "Lead 8 (Bass+Lead)",
    // Synth Pad (88-95)
    "Pad 1 (New Age)", "Pad 2 (Warm)", "Pad 3 (Polysynth)", "Pad 4 (Choir)",
    "Pad 5 (Bowed)", "Pad 6 (Metallic)", "Pad 7 (Halo)", "Pad 8 (Sweep)",
    // Synth Effects (96-103)
    "FX 1 (Rain)", "FX 2 (Soundtrack)", "FX 3 (Crystal)", "FX 4 (Atmosphere)",
    "FX 5 (Brightness)", "FX 6 (Goblins)", "FX 7 (Echoes)", "FX 8 (Sci-fi)",
    // Ethnic (104-111)
    "Sitar", "Banjo", "Shamisen", "Koto",
    "Kalimba", "Bagpipe", "Fiddle", "Shanai",
    // Percussive (112-119)
    "Tinkle Bell", "Agogo", "Steel Drums", "Woodblock",
    "Taiko Drum", "Melodic Tom", "Synth Drum", "Reverse Cymbal",
    // Sound Effects (120-127)
    "Guitar Fret Noise", "Breath Noise", "Seashore", "Bird Tweet",
    "Telephone Ring", "Helicopter", "Applause", "Gunshot",
]

struct SongEntry: Identifiable {
    let id = UUID()
    let name: String
    let source: SongSource
}

enum SongSource {
    case midiFile(URL)
}


// MARK: - MIDI Loader

final class MIDILoader {

    // MARK: - Track-level loading

    /// Load a MIDI file and return info + notes for each track separately.
    static func loadMIDITracks(from url: URL) -> [(info: MIDITrackInfo, notes: [GameNote])]? {
        var sequence: MusicSequence?
        guard NewMusicSequence(&sequence) == noErr, let seq = sequence else { return nil }

        guard MusicSequenceFileLoad(seq, url as CFURL, .midiType, []) == noErr else {
            DisposeMusicSequence(seq)
            return nil
        }

        var trackCount: UInt32 = 0
        MusicSequenceGetTrackCount(seq, &trackCount)

        var result: [(info: MIDITrackInfo, notes: [GameNote])] = []

        for i in 0..<trackCount {
            var track: MusicTrack?
            MusicSequenceGetIndTrack(seq, i, &track)
            guard let track = track else { continue }

            var notes: [GameNote] = []
            var trackName = "Track \(i + 1)"
            var instrumentName: String?

            var iterator: MusicEventIterator?
            NewMusicEventIterator(track, &iterator)
            guard let iter = iterator else { continue }

            var hasEvent: DarwinBoolean = true
            MusicEventIteratorHasCurrentEvent(iter, &hasEvent)

            while hasEvent.boolValue {
                var timestamp: MusicTimeStamp = 0
                var eventType: MusicEventType = 0
                var eventData: UnsafeRawPointer?
                var eventDataSize: UInt32 = 0

                MusicEventIteratorGetEventInfo(iter, &timestamp, &eventType, &eventData, &eventDataSize)

                if eventType == kMusicEventType_MIDINoteMessage, let data = eventData {
                    let msg = data.assumingMemoryBound(to: MIDINoteMessage.self).pointee

                    var seconds: Float64 = 0
                    MusicSequenceGetSecondsForBeats(seq, timestamp, &seconds)
                    var endSeconds: Float64 = 0
                    MusicSequenceGetSecondsForBeats(seq, timestamp + Float64(msg.duration), &endSeconds)

                    let freq = 440.0 * pow(2.0, (Double(msg.note) - 69.0) / 12.0)
                    notes.append(GameNote(
                        time: seconds, frequency: freq,
                        duration: max(endSeconds - seconds, 0.05), midiNote: msg.note
                    ))
                } else if eventType == kMusicEventType_MIDIChannelMessage, let data = eventData {
                    // Program change (0xC0) → instrument
                    let msg = data.assumingMemoryBound(to: MIDIChannelMessage.self).pointee
                    if (msg.status & 0xF0) == 0xC0 {
                        let program = Int(msg.data1)
                        if program < gmInstrumentNames.count {
                            instrumentName = gmInstrumentNames[program]
                        }
                    }
                } else if eventType == kMusicEventType_Meta, let data = eventData {
                    let meta = data.assumingMemoryBound(to: MIDIMetaEvent.self).pointee
                    if meta.dataLength > 0 {
                        let ptr = data.advanced(by: MemoryLayout<MIDIMetaEvent>.offset(of: \MIDIMetaEvent.data)!)
                        let bytes = Array(UnsafeBufferPointer(
                            start: ptr.assumingMemoryBound(to: UInt8.self),
                            count: Int(meta.dataLength)
                        ))
                        if meta.metaEventType == 3 {
                            // Track name
                            if let name = String(bytes: bytes, encoding: .utf8), !name.isEmpty {
                                trackName = name
                            }
                        } else if meta.metaEventType == 4 {
                            // Instrument name meta event
                            if let name = String(bytes: bytes, encoding: .utf8), !name.isEmpty {
                                instrumentName = name
                            }
                        }
                    }
                }

                MusicEventIteratorNextEvent(iter)
                MusicEventIteratorHasCurrentEvent(iter, &hasEvent)
            }

            DisposeMusicEventIterator(iter)

            // Only include tracks with notes
            guard !notes.isEmpty else { continue }

            let sorted = deduplicateSimultaneous(notes.sorted { $0.time < $1.time })
            let midiNotes = sorted.map { $0.midiNote }
            let info = MIDITrackInfo(
                id: Int(i),
                noteCount: sorted.count,
                lowestNote: midiNotes.min()!,
                highestNote: midiNotes.max()!,
                name: trackName,
                instrument: instrumentName
            )

            result.append((info: info, notes: sorted))
        }

        DisposeMusicSequence(seq)
        return result.isEmpty ? nil : result
    }

    /// Load all notes from a MIDI file (merged tracks).
    static func loadMIDI(from url: URL) -> [GameNote]? {
        guard let tracks = loadMIDITracks(from: url) else { return nil }
        return tracks.flatMap { $0.notes }.sorted { $0.time < $1.time }
    }


    // MARK: - Simultaneous note deduplication

    /// When multiple notes start at (nearly) the same time, keep only the lowest pitch.
    static func deduplicateSimultaneous(_ notes: [GameNote], threshold: Double = 0.02) -> [GameNote] {
        guard !notes.isEmpty else { return notes }
        var result: [GameNote] = []
        var i = 0
        while i < notes.count {
            var j = i + 1
            // Collect all notes starting within threshold of this one
            while j < notes.count && abs(notes[j].time - notes[i].time) < threshold {
                j += 1
            }
            // Pick the one with the lowest MIDI note (lowest pitch)
            let group = notes[i..<j]
            if let lowest = group.min(by: { $0.midiNote < $1.midiNote }) {
                result.append(lowest)
            }
            i = j
        }
        return result
    }

    // MARK: - File scanning

    static func scanTracks(in directory: URL) -> [URL] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return [] }
        return contents
            .filter { ["mid", "midi"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: - Bundled tracks

    /// Copy bundled MIDI files to the tracks directory if they don't already exist.
    static func copyBundledTracks(to directory: URL) {
        guard let bundledURL = Bundle.module.url(forResource: "Tracks", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(
                  at: bundledURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        else { return }

        let fm = FileManager.default
        for file in files where ["mid", "midi"].contains(file.pathExtension.lowercased()) {
            let dest = directory.appendingPathComponent(file.lastPathComponent)
            if !fm.fileExists(atPath: dest.path) {
                try? fm.copyItem(at: file, to: dest)
            }
        }
    }
}
