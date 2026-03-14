# Display Champ

Knockoff Trombone Champ for MacBook — control pitch by tilting the laptop lid.

## How it works

Your MacBook has a hidden lid angle sensor. Display Champ reads it via IOKit to map the lid angle to pitch — open the lid wider to go higher, close it to go lower. Hold **Space** or **click** to blow. Notes scroll across the screen and you try to match pitch. It's exactly as ridiculous as it sounds.

## Features

- **Lid angle = pitch** — reads the hardware HID sensor at ~60Hz, smoothed
- **Brass synthesis** — real-time additive synthesis (8 harmonics) through AVAudioEngine
- **MIDI support** — load any `.mid` file, pick which track to play, the rest plays as backing
- **Starter track** — Good King Wenceslas auto-generated on first launch
- **Freestyle mode** — just noodle with no notes
- **Calibration** — set your lid angle range, persisted across sessions
- **Scoring** — per-note accuracy (Perfect/Good/OK/Miss), combo multiplier, letter grades S–F
- **Track selection** — multi-track MIDIs show instrument names (General MIDI), pick your part

Drop `.mid` files into `~/Library/Application Support/DisplayChamp/tracks` or use the "Open Folder" button in-app.

## Compatibility

Requires a **MacBook with a lid angle sensor** (most models 2012+) running **macOS 14 Sonoma or later**. The sensor is read passively via IOKit — if your Mac doesn't have one, pitch defaults to mouse Y position as a fallback.

Not tested on desktop Macs (no lid = no sensor). External displays won't help.

## Disclaimer

This game encourages you to repeatedly open and close your laptop lid. You do this at your own risk. The author is not responsible for worn hinges, cracked displays, spilled drinks caused by aggressive tromboning, or any other damage to your hardware, dignity, or relationships.

## Install

### From source

```
git clone https://github.com/laszloKopits/display-champ.git
cd display-champ
swift build -c release
open .build/release/DisplayChamp.app
```

### Pre-built

Download `DisplayChamp.zip` from [Releases](https://github.com/laszloKopits/display-champ/releases), unzip, right-click → Open (bypasses Gatekeeper).

## Tech

- Swift + SwiftUI, macOS 14+, Swift Package Manager
- IOKit HID sensor (VID `0x05AC`, PID `0x8104`) with mouse Y fallback
- AVAudioEngine + AVAudioSourceNode (44.1kHz additive synthesis)
- AudioToolbox MusicSequence (MIDI loading + backing track playback)
- No external dependencies

## Credits

MIDI files from [Mutopia Project](https://www.mutopiaproject.org) (public domain).
