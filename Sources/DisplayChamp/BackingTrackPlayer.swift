import AudioToolbox
import Foundation

/// Plays a MIDI file using the system synth, with one track muted (the player's track).
final class BackingTrackPlayer {
    private var sequence: MusicSequence?
    private var player: MusicPlayer?
    private var isPlaying = false

    /// Prepare a MIDI file for playback with one track muted.
    /// - Parameters:
    ///   - url: Path to the .mid file
    ///   - muteTrackIndex: The track index to mute (the player's track)
    ///   - volume: 0.0 to 1.0 (not directly supported, but we can try)
    func prepare(midiURL url: URL, muteTrackIndex: Int) {
        cleanup()

        var seq: MusicSequence?
        guard NewMusicSequence(&seq) == noErr, let seq = seq else { return }
        self.sequence = seq

        guard MusicSequenceFileLoad(seq, url as CFURL, .midiType, []) == noErr else {
            cleanup()
            return
        }

        // Mute the selected track
        var trackCount: UInt32 = 0
        MusicSequenceGetTrackCount(seq, &trackCount)

        var noteTrackIndex = 0
        for i in 0..<trackCount {
            var track: MusicTrack?
            MusicSequenceGetIndTrack(seq, i, &track)
            guard let track = track else { continue }

            // Check if this track has notes
            var hasNotes = false
            var iter: MusicEventIterator?
            NewMusicEventIterator(track, &iter)
            if let iter = iter {
                var hasEvent: DarwinBoolean = true
                MusicEventIteratorHasCurrentEvent(iter, &hasEvent)
                while hasEvent.boolValue {
                    var timestamp: MusicTimeStamp = 0
                    var eventType: MusicEventType = 0
                    var eventData: UnsafeRawPointer?
                    var eventDataSize: UInt32 = 0
                    MusicEventIteratorGetEventInfo(iter, &timestamp, &eventType, &eventData, &eventDataSize)
                    if eventType == kMusicEventType_MIDINoteMessage {
                        hasNotes = true
                        break
                    }
                    MusicEventIteratorNextEvent(iter)
                    MusicEventIteratorHasCurrentEvent(iter, &hasEvent)
                }
                DisposeMusicEventIterator(iter)
            }

            if hasNotes {
                if noteTrackIndex == muteTrackIndex {
                    // Mute this track
                    var mute: DarwinBoolean = true
                    MusicTrackSetProperty(track, kSequenceTrackProperty_MuteStatus,
                                          &mute, UInt32(MemoryLayout<DarwinBoolean>.size))
                }
                noteTrackIndex += 1
            }
        }

        // Create player
        var p: MusicPlayer?
        guard NewMusicPlayer(&p) == noErr, let p = p else {
            cleanup()
            return
        }
        self.player = p

        MusicPlayerSetSequence(p, seq)
        MusicPlayerPreroll(p)
    }

    func start() {
        guard let player = player, !isPlaying else { return }
        MusicPlayerStart(player)
        isPlaying = true
    }

    func stop() {
        guard let player = player, isPlaying else { return }
        MusicPlayerStop(player)
        isPlaying = false
    }

    func cleanup() {
        if let player = player {
            if isPlaying { MusicPlayerStop(player) }
            DisposeMusicPlayer(player)
        }
        if let sequence = sequence {
            DisposeMusicSequence(sequence)
        }
        player = nil
        sequence = nil
        isPlaying = false
    }

    deinit {
        cleanup()
    }
}
