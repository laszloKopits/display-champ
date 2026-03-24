import SwiftUI

// MARK: - Stars

private struct Star {
    let x, y, size, twinkleSpeed, phase: Double
}

private let stars: [Star] = {
    var s: UInt64 = 42
    func r() -> Double { s = s &* 6364136223846793005 &+ 1; return Double(s >> 33) / Double(UInt32.max) }
    return (0..<60).map { _ in Star(x: r(), y: r(), size: 0.5 + r() * 1.5, twinkleSpeed: 0.3 + r() * 2, phase: r() * .pi * 2) }
}()

// MARK: - Main View

struct GameView: View {
    @ObservedObject var gameState: GameState
    var onOpenTracksFolder: (() -> Void)?
    var onRefreshSongs: (() -> Void)?
    @AppStorage("DisplayChamp_DisclaimerAccepted") private var disclaimerAccepted = false
    @State private var disclaimerChecked = false

    var body: some View {
        ZStack {
            // Background always animates (stars twinkling)
            TimelineView(.animation) { timeline in
                background(time: timeline.date.timeIntervalSinceReferenceDate)
            }

            if !disclaimerAccepted {
                disclaimerScreen
            } else {
                // Interactive screens rendered outside TimelineView so buttons work
                switch gameState.phase {
                case .menu:
                    menuScreen()
                case .trackSelect:
                    trackSelectScreen
                case .calibrateLow:
                    calibrateScreen(step: "low")
                case .calibrateHigh:
                    calibrateScreen(step: "high")
                case .countdown, .playing, .finished, .freestyle:
                    TimelineView(.animation) { timeline in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        switch gameState.phase {
                        case .countdown:
                            countdownScreen(time: t)
                        case .playing:
                            gameplayView(time: t)
                        case .finished:
                            endScreen(time: t)
                        case .freestyle:
                            freestyleView(time: t)
                        default:
                            EmptyView()
                        }
                    }
                }

                // Note guide overlay on all screens (except gameplay/freestyle which have their own)
                if gameState.phase != .playing && gameState.phase != .freestyle {
                    noteGuideOverlay
                }
            }
        }
        .frame(minWidth: 700, minHeight: 400)
    }

    // MARK: - Note Guide Overlay

    private var noteGuideOverlay: some View {
        Canvas { ctx, size in
            let guideW: CGFloat = 60
            let x = size.width - guideW
            let topP: CGFloat = 30, botP: CGFloat = 30
            let hH = size.height - topP - botP

            // Dim background strip
            ctx.fill(Path(CGRect(x: x, y: 0, width: guideW, height: size.height)),
                     with: .color(.black.opacity(0.25)))

            // Note lines
            let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
            for midi in 48...84 {
                let freq = 440.0 * pow(2.0, (Double(midi) - 69.0) / 12.0)
                let ny = gameState.normalizedPitch(for: freq)
                guard ny > 0.01 && ny < 0.99 else { continue }
                let y = topP + hH * (1 - CGFloat(ny))
                let isNatural = ![1, 3, 6, 8, 10].contains(midi % 12)

                var line = Path()
                line.move(to: CGPoint(x: x, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(line, with: .color(.white.opacity(isNatural ? 0.12 : 0.04)), lineWidth: 1)

                if isNatural {
                    let name = noteNames[midi % 12]
                    let octave = midi / 12 - 1
                    ctx.draw(Text("\(name)\(octave)")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3)),
                             at: CGPoint(x: x + guideW / 2, y: y - 6))
                }
            }

            // Cursor
            let cY = topP + hH * (1 - CGFloat(gameState.cursorY))
            let isB = gameState.isBlowing
            let cc: Color = isB ? .orange : .cyan.opacity(0.6)

            // Glow
            if isB {
                ctx.fill(RoundedRectangle(cornerRadius: 4).path(in:
                    CGRect(x: x - 2, y: cY - 6, width: guideW + 4, height: 12)),
                         with: .color(.orange.opacity(0.15)))
            }

            // Line
            var cursorLine = Path()
            cursorLine.move(to: CGPoint(x: x, y: cY))
            cursorLine.addLine(to: CGPoint(x: size.width, y: cY))
            ctx.stroke(cursorLine, with: .color(cc), lineWidth: isB ? 2 : 1.5)

            // Arrow
            var arrow = Path()
            arrow.move(to: CGPoint(x: x - 5, y: cY - 4))
            arrow.addLine(to: CGPoint(x: x, y: cY))
            arrow.addLine(to: CGPoint(x: x - 5, y: cY + 4))
            arrow.closeSubpath()
            ctx.fill(arrow, with: .color(cc))

            // Note name
            ctx.draw(Text(currentNoteName)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(isB ? .orange : .white.opacity(0.5)),
                     at: CGPoint(x: x - 18, y: cY))
        }
        .allowsHitTesting(false)
    }

    // MARK: - Background

    private func background(time: Double) -> some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [Color(red: 0.03, green: 0.01, blue: 0.12),
                                  Color(red: 0.08, green: 0.03, blue: 0.22)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            for star in stars {
                let tw = 0.3 + 0.7 * (0.5 + 0.5 * sin(time * star.twinkleSpeed + star.phase))
                ctx.opacity = tw
                ctx.fill(Circle().path(in: CGRect(
                    x: star.x * size.width - star.size / 2,
                    y: star.y * size.height - star.size / 2,
                    width: star.size, height: star.size
                )), with: .color(.white))
            }
            ctx.opacity = 1
        }
        .ignoresSafeArea()
    }

    // MARK: - Menu Screen

    private func menuScreen() -> some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                // Left side: title + controls
                VStack(spacing: 14) {
                    Spacer()

                    Text("DISPLAY CHAMP")
                        .font(.system(size: min(40, geo.size.width * 0.045), weight: .black, design: .rounded))
                        .foregroundStyle(LinearGradient(
                            colors: [Color(red: 1, green: 0.85, blue: 0), Color(red: 1, green: 0.5, blue: 0)],
                            startPoint: .leading, endPoint: .trailing))
                        .shadow(color: .orange.opacity(0.5), radius: 16)

                    // Angle meter
                    angleMeter.frame(width: min(260, geo.size.width * 0.29), height: 50)

                    VStack(spacing: 4) {
                        Text("Tilt display = pitch").font(.caption).foregroundColor(.white.opacity(0.4))
                        Text("Click/Space = play note").font(.caption).foregroundColor(.white.opacity(0.4))
                    }

                    Button(action: { gameState.phase = .freestyle }) {
                        HStack(spacing: 6) {
                            Image(systemName: "music.note")
                            Text("FREESTYLE")
                        }
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 7)
                        .background(Color.cyan.opacity(0.1))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cyan.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Button(action: { gameState.snapToNote.toggle() }) {
                        HStack(spacing: 6) {
                            Image(systemName: gameState.snapToNote ? "checkmark.square.fill" : "square")
                                .foregroundColor(gameState.snapToNote ? .yellow : .white.opacity(0.4))
                            Text("Cheater Mode")
                                .foregroundColor(gameState.snapToNote ? .yellow : .white.opacity(0.5))
                        }
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 12) {
                        Text("C = calibrate").font(.caption2).foregroundColor(.white.opacity(0.3))
                        Text("F = fullscreen").font(.caption2).foregroundColor(.white.opacity(0.3))
                    }

                    if gameState.calibration.isCalibrated {
                        Text("Calibrated: \(Int(gameState.calibration.minAngle))°-\(Int(gameState.calibration.maxAngle))°")
                            .font(.caption2).foregroundColor(.green.opacity(0.4))
                    }

                    Spacer()
                }
                .frame(width: geo.size.width * 0.38)

            // Right side: song list
            VStack(alignment: .leading, spacing: 8) {
                Text("SELECT SONG")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.top, 20)

                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(Array(gameState.songs.enumerated()), id: \.element.id) { index, song in
                            songRow(song: song, index: index, isSelected: index == gameState.selectedSongIndex)
                        }
                    }
                }

                // Folder / Refresh buttons
                HStack(spacing: 8) {
                    Button(action: { onOpenTracksFolder?() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                            Text("Open Folder")
                        }
                        .font(.caption)
                        .foregroundColor(.cyan.opacity(0.7))
                    }
                    .buttonStyle(.plain)

                    Button(action: { onRefreshSongs?() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh")
                        }
                        .font(.caption)
                        .foregroundColor(.cyan.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 10)

                // Play button
                Button(action: {
                    gameState.selectSong(at: gameState.selectedSongIndex)
                    if gameState.phase != .trackSelect {
                        gameState.startCountdown()
                    }
                }) {
                    Text("PLAY")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing)
                        )
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
        }
        }
    }

    private func songRow(song: SongEntry, index: Int, isSelected: Bool) -> some View {
        Button(action: { gameState.selectedSongIndex = index }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.name)
                        .font(.system(size: 13, weight: isSelected ? .bold : .regular))
                        .foregroundColor(isSelected ? .yellow : .white)
                }
                Spacer()
                if isSelected {
                    Circle().fill(Color.yellow).frame(width: 6, height: 6)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(isSelected ? Color.white.opacity(0.07) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private var angleMeter: some View {
        Canvas { ctx, size in
            let pad: CGFloat = 16
            let barW = size.width - pad * 2
            let barY = size.height / 2

            ctx.fill(RoundedRectangle(cornerRadius: 3).path(in:
                CGRect(x: pad, y: barY - 3, width: barW, height: 6)),
                     with: .color(.white.opacity(0.08)))

            let pos = CGFloat(gameState.normalizedAngle)
            let cx = pad + pos * barW

            ctx.fill(Circle().path(in: CGRect(x: cx - 10, y: barY - 10, width: 20, height: 20)),
                     with: .color(.orange.opacity(0.15)))
            ctx.fill(Circle().path(in: CGRect(x: cx - 6, y: barY - 6, width: 12, height: 12)),
                     with: .color(.orange))

            ctx.draw(Text("\(Int(gameState.currentAngle))°").font(.caption2.bold()).foregroundColor(.orange),
                     at: CGPoint(x: cx, y: barY - 18))
            ctx.draw(Text("Low").font(.system(size: 8)).foregroundColor(.white.opacity(0.25)),
                     at: CGPoint(x: pad + 10, y: barY + 14))
            ctx.draw(Text("High").font(.system(size: 8)).foregroundColor(.white.opacity(0.25)),
                     at: CGPoint(x: pad + barW - 12, y: barY + 14))
        }
    }

    // MARK: - Track Select Screen

    private var trackSelectScreen: some View {
        VStack(spacing: 16) {
            Text("SELECT YOUR TRACK")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundColor(.white)

            Text("Pick the track you want to play. Other tracks will be your backing band.")
                .font(.callout)
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Array(gameState.midiTracks.enumerated()), id: \.offset) { index, track in
                        Button(action: {
                            gameState.selectTrack(index)
                            gameState.startCountdown()
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.info.displayName)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                    HStack(spacing: 8) {
                                        Text("\(track.info.noteCount) notes")
                                        Text(track.info.rangeString)
                                        if let inst = track.info.instrument {
                                            Text(inst)
                                                .foregroundColor(.cyan.opacity(0.6))
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.4))
                                }
                                Spacer()
                                Text("PLAY")
                                    .font(.caption.bold())
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(Color.yellow)
                                    .cornerRadius(4)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 14)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: 600)

            Button(action: { gameState.phase = .menu }) {
                Text("Back").font(.callout).foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    // MARK: - Calibration

    private func calibrateScreen(step: String) -> some View {
        VStack(spacing: 20) {
            Text("CALIBRATE").font(.system(size: 28, weight: .black, design: .rounded)).foregroundColor(.white)

            Text(step == "low"
                 ? "Tilt your display to the LOWEST pitch position"
                 : "Now tilt to the HIGHEST pitch position")
                .foregroundColor(.white.opacity(0.7))

            Text("\(Int(gameState.currentAngle))°")
                .font(.system(size: 56, weight: .black, design: .monospaced))
                .foregroundColor(.orange)

            angleMeter.frame(width: 300, height: 50)

            Text("Click to set").font(.headline).foregroundColor(.yellow)
        }
    }

    // MARK: - Countdown

    private func countdownScreen(time: Double) -> some View {
        let pulse = 1.0 + 0.12 * sin(time * 8)
        return ZStack {
            // Show the gameplay canvas so player can see incoming notes and their cursor
            gameCanvas(time: time)

            // Dim overlay so countdown text pops
            Color.black.opacity(0.3).allowsHitTesting(false)

            // Countdown number
            VStack(spacing: 10) {
                Text(gameState.trackName)
                    .font(.title3.bold())
                    .foregroundColor(.white.opacity(0.7))
                if gameState.countdown > 0 {
                    Text("\(gameState.countdown)")
                        .font(.system(size: 96, weight: .black, design: .rounded))
                        .foregroundColor(.yellow).scaleEffect(pulse)
                        .shadow(color: .orange.opacity(0.6), radius: 24)
                        .shadow(color: .black.opacity(0.5), radius: 8)
                } else {
                    Text("GO!")
                        .font(.system(size: 72, weight: .black, design: .rounded))
                        .foregroundColor(.green)
                        .shadow(color: .green.opacity(0.6), radius: 24)
                        .shadow(color: .black.opacity(0.5), radius: 8)
                }
                Text("Get ready!")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    // MARK: - Gameplay

    private func gameplayView(time: Double) -> some View {
        ZStack {
            gameCanvas(time: time)
            hudOverlay
            popupOverlay
            progressBar
        }
    }

    private func gameCanvas(time: Double) -> some View {
        Canvas { ctx, size in
            let phX: CGFloat = 140, topP: CGFloat = 50, botP: CGFloat = 55
            let hH = size.height - topP - botP
            let pps: CGFloat = 180

            // Pitch guides
            for freq in gameState.uniquePitches {
                let ny = gameState.normalizedPitch(for: freq)
                let y = topP + hH * (1 - CGFloat(ny))
                var line = Path(); line.move(to: CGPoint(x: phX, y: y)); line.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(line, with: .color(.white.opacity(0.035)), lineWidth: 1)
            }

            // Playhead
            let phGlow = gameState.isBlowing ? 0.3 : 0.1
            for w in [8.0, 3.0, 1.0] as [CGFloat] {
                var l = Path(); l.move(to: CGPoint(x: phX, y: topP)); l.addLine(to: CGPoint(x: phX, y: topP + hH))
                ctx.stroke(l, with: .color(Color.cyan.opacity(phGlow * Double(1.5 / w))), lineWidth: w)
            }

            // Notes
            for note in gameState.visibleNotes {
                let ny = gameState.normalizedPitch(for: note.frequency)
                let nY = topP + hH * (1 - CGFloat(ny))
                let nX = phX + CGFloat(note.time - gameState.currentTime) * pps
                let nW = max(CGFloat(note.duration) * pps, 22)
                let nH: CGFloat = 18
                let rect = CGRect(x: nX, y: nY - nH / 2, width: nW, height: nH)

                let isActive = gameState.currentTime >= note.time - 0.15 && gameState.currentTime <= note.time + note.duration + 0.15
                let result = gameState.accuracyForNote(note)
                let isPassed = note.time + note.duration < gameState.currentTime

                let fill: Color, border: Color, glow: Double
                if isActive && gameState.isBlowing {
                    fill = gameState.currentAccuracy.color; border = fill
                    glow = gameState.currentAccuracy == .perfect ? 0.35 : 0.12
                } else if isPassed {
                    fill = (result?.color ?? .white).opacity(0.12); border = .clear; glow = 0
                } else {
                    fill = Color(red: 0.2, green: 0.4, blue: 0.85); border = Color(red: 0.3, green: 0.5, blue: 1); glow = 0.04
                }

                if glow > 0 {
                    ctx.fill(RoundedRectangle(cornerRadius: 12).path(in: rect.insetBy(dx: -5, dy: -5)),
                             with: .color(fill.opacity(glow)))
                }
                let np = RoundedRectangle(cornerRadius: 5).path(in: rect)
                ctx.fill(np, with: .color(fill))
                if border != .clear { ctx.stroke(np, with: .color(border.opacity(0.4)), lineWidth: 1) }
                if nW > 28 && !isPassed {
                    ctx.draw(Text(note.noteName).font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7)), at: CGPoint(x: nX + nW / 2, y: nY))
                }
            }

            // Trombone
            drawTrombone(ctx: &ctx, topPad: topP, highwayH: hH, time: time)

            // Cursor
            let cY = topP + hH * (1 - CGFloat(gameState.cursorY))
            let isB = gameState.isBlowing
            let cc: Color = isB ? .orange : .white.opacity(0.5)
            let lW: CGFloat = isB ? 45 : 35
            ctx.fill(RoundedRectangle(cornerRadius: 1.5).path(in:
                CGRect(x: phX - lW / 2, y: cY - 1.5, width: lW, height: 3)), with: .color(cc))
            if isB {
                ctx.fill(RoundedRectangle(cornerRadius: 5).path(in:
                    CGRect(x: phX - lW / 2 - 4, y: cY - 5, width: lW + 8, height: 10)),
                         with: .color(.orange.opacity(0.12)))
            }
            var arrow = Path()
            let ax = phX - lW / 2 - 5
            arrow.move(to: CGPoint(x: ax, y: cY - 6))
            arrow.addLine(to: CGPoint(x: ax + 7, y: cY))
            arrow.addLine(to: CGPoint(x: ax, y: cY + 6))
            arrow.closeSubpath()
            ctx.fill(arrow, with: .color(cc))
        }
    }

    private func drawTrombone(ctx: inout GraphicsContext, topPad: CGFloat, highwayH: CGFloat, time: Double) {
        let cY = topPad + highwayH * (1 - CGFloat(gameState.cursorY))
        let bellX: CGFloat = 100
        let slideLen = CGFloat(1 - gameState.cursorY) * 70 + 18
        let sX = bellX - slideLen
        let isB = gameState.isBlowing
        let brass = Color(red: 0.82, green: 0.68, blue: 0.2)
        let brassL = Color(red: 0.92, green: 0.78, blue: 0.3)
        let brassD = Color(red: 0.6, green: 0.48, blue: 0.12)

        let bW: CGFloat = isB ? 24 : 18
        let bH: CGFloat = isB ? 28 : 22
        var bell = Path()
        bell.move(to: CGPoint(x: bellX - 3, y: cY - 3.5))
        bell.addCurve(to: CGPoint(x: bellX + bW, y: cY - bH / 2),
                      control1: CGPoint(x: bellX + 5, y: cY - 3.5),
                      control2: CGPoint(x: bellX + bW - 3, y: cY - bH / 3))
        bell.addLine(to: CGPoint(x: bellX + bW, y: cY + bH / 2))
        bell.addCurve(to: CGPoint(x: bellX - 3, y: cY + 3.5),
                      control1: CGPoint(x: bellX + bW - 3, y: cY + bH / 3),
                      control2: CGPoint(x: bellX + 5, y: cY + 3.5))
        bell.closeSubpath()

        if isB { ctx.fill(Ellipse().path(in: CGRect(x: bellX - 1, y: cY - bH / 2 - 4, width: bW + 6, height: bH + 8)),
                          with: .color(.orange.opacity(0.1))) }
        ctx.fill(bell, with: .color(isB ? brassL : brass))
        ctx.stroke(bell, with: .color(brassD.opacity(0.5)), lineWidth: 0.8)

        let gap: CGFloat = 4.5, th: CGFloat = 2.2
        ctx.fill(Path(CGRect(x: sX, y: cY - gap / 2 - th / 2, width: bellX - sX, height: th)), with: .color(brass))
        ctx.fill(Path(CGRect(x: sX, y: cY + gap / 2 - th / 2, width: bellX - sX, height: th)), with: .color(brass))

        var uBend = Path()
        uBend.move(to: CGPoint(x: sX, y: cY - gap / 2 - th / 2))
        uBend.addQuadCurve(to: CGPoint(x: sX, y: cY + gap / 2 + th / 2),
                           control: CGPoint(x: sX - 8, y: cY))
        ctx.stroke(uBend, with: .color(brass), lineWidth: 2.2)
    }

    // MARK: - HUD

    private var hudOverlay: some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("SCORE").font(.system(size: 10, weight: .bold)).foregroundColor(.white.opacity(0.4))
                    Text("\(gameState.score)")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundColor(.white).contentTransition(.numericText())
                }
                Spacer()
                if gameState.currentAccuracy != .none {
                    Text(gameState.currentAccuracy.label)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(gameState.currentAccuracy.color)
                        .shadow(color: gameState.currentAccuracy.color.opacity(0.5), radius: 8)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("COMBO").font(.system(size: 10, weight: .bold)).foregroundColor(.white.opacity(0.4))
                    HStack(spacing: 3) {
                        let mult = min(1.0 + Double(gameState.combo) / 10.0, 4.0)
                        if mult > 1.0 {
                            Text("x\(String(format: "%.1f", mult))")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(.yellow.opacity(0.6))
                        }
                        Text("\(gameState.combo)")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundColor(gameState.combo >= 10 ? .yellow : .white)
                            .contentTransition(.numericText())
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 10)
            Spacer()
            if gameState.snapToNote {
                HStack {
                    Text("CHEATER MODE")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(.yellow.opacity(0.5))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.yellow.opacity(0.08))
                        .cornerRadius(4)
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.bottom, 12)
            }
        }
    }

    private var popupOverlay: some View {
        Canvas { ctx, size in
            let topP: CGFloat = 50, botP: CGFloat = 55
            let hH = size.height - topP - botP
            for popup in gameState.popups {
                let age = gameState.currentTime - popup.birthTime
                guard age >= 0 && age < 1 else { continue }
                let y = topP + hH * (1 - CGFloat(popup.normalizedY)) - CGFloat(age) * 35
                ctx.opacity = max(0, 1 - age * 1.3)
                ctx.draw(Text(popup.accuracy.label)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(popup.accuracy.color), at: CGPoint(x: 195, y: y))
            }
            ctx.opacity = 1
        }
        .allowsHitTesting(false)
    }

    private var progressBar: some View {
        VStack {
            Spacer()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.06)).frame(height: 2.5)
                    Rectangle()
                        .fill(LinearGradient(colors: [.cyan.opacity(0.5), .blue.opacity(0.3)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(gameState.progress), height: 2.5)
                }
            }
            .frame(height: 2.5).padding(.bottom, 6)
        }
    }

    // MARK: - Freestyle

    private func freestyleView(time: Double) -> some View {
        ZStack {
            // Main canvas: trombone + cursor + note name
            Canvas { ctx, size in
                let topP: CGFloat = 60, botP: CGFloat = 60
                let hH = size.height - topP - botP

                // Pitch guide lines (chromatic scale across range)
                let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
                for midi in 48...84 { // C3 to C6
                    let freq = 440.0 * pow(2.0, (Double(midi) - 69.0) / 12.0)
                    let ny = gameState.normalizedPitch(for: freq)
                    guard ny > 0.01 && ny < 0.99 else { continue }
                    let y = topP + hH * (1 - CGFloat(ny))
                    let isNatural = ![1,3,6,8,10].contains(midi % 12)
                    var line = Path()
                    line.move(to: CGPoint(x: 140, y: y))
                    line.addLine(to: CGPoint(x: size.width - 20, y: y))
                    ctx.stroke(line, with: .color(.white.opacity(isNatural ? 0.06 : 0.025)), lineWidth: 1)
                    if isNatural {
                        let name = noteNames[midi % 12]
                        let octave = midi / 12 - 1
                        ctx.draw(Text("\(name)\(octave)").font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.white.opacity(0.15)),
                                 at: CGPoint(x: size.width - 10, y: y))
                    }
                }

                // Trombone
                drawTrombone(ctx: &ctx, topPad: topP, highwayH: hH, time: time)

                // Cursor
                let cY = topP + hH * (1 - CGFloat(gameState.cursorY))
                let isB = gameState.isBlowing
                let cc: Color = isB ? .orange : .white.opacity(0.5)
                // Extended pitch line when blowing
                if isB {
                    ctx.fill(RoundedRectangle(cornerRadius: 1).path(in:
                        CGRect(x: 140, y: cY - 0.5, width: size.width - 160, height: 1)),
                             with: .color(.orange.opacity(0.15)))
                }

                ctx.fill(RoundedRectangle(cornerRadius: 1.5).path(in:
                    CGRect(x: 115, y: cY - 1.5, width: isB ? 50 : 35, height: 3)), with: .color(cc))
                if isB {
                    ctx.fill(RoundedRectangle(cornerRadius: 5).path(in:
                        CGRect(x: 111, y: cY - 5, width: 58, height: 10)),
                             with: .color(.orange.opacity(0.12)))
                }
                var arrow = Path()
                let ax: CGFloat = 110
                arrow.move(to: CGPoint(x: ax, y: cY - 6))
                arrow.addLine(to: CGPoint(x: ax + 7, y: cY))
                arrow.addLine(to: CGPoint(x: ax, y: cY + 6))
                arrow.closeSubpath()
                ctx.fill(arrow, with: .color(cc))
            }

            // Current note name overlay
            VStack {
                HStack {
                    Spacer()
                    VStack(spacing: 2) {
                        Text(currentNoteName)
                            .font(.system(size: 48, weight: .black, design: .rounded))
                            .foregroundColor(gameState.isBlowing ? .orange : .white.opacity(0.2))
                            .shadow(color: gameState.isBlowing ? .orange.opacity(0.3) : .clear, radius: 12)
                        Text("\(Int(gameState.currentFrequency)) Hz")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(gameState.isBlowing ? .white.opacity(0.5) : .white.opacity(0.15))
                    }
                    .padding(.trailing, 40)
                    .padding(.top, 20)
                }
                Spacer()
            }

            // Bottom hint
            VStack {
                Spacer()
                HStack {
                    Text("FREESTYLE")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.cyan.opacity(0.4))
                    Spacer()
                    Text("Esc = back")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.25))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
    }

    private var currentNoteName: String {
        let freq = gameState.currentFrequency
        let midiFloat = 69.0 + 12.0 * log2(freq / 440.0)
        let midi = Int(round(midiFloat))
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let note = names[((midi % 12) + 12) % 12]
        let octave = midi / 12 - 1
        return "\(note)\(octave)"
    }

    // MARK: - Disclaimer

    private var disclaimerScreen: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("DISPLAY CHAMP")
                .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundStyle(LinearGradient(
                    colors: [Color(red: 1, green: 0.85, blue: 0), Color(red: 1, green: 0.5, blue: 0)],
                    startPoint: .leading, endPoint: .trailing))
                .shadow(color: .orange.opacity(0.5), radius: 16)

            VStack(spacing: 8) {
                Text("Before you play...")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.7))
                Text("This game uses your MacBook's lid angle sensor.\nYou will be tilting your display back and forth to control pitch.")
                    .font(.callout)
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }

            Button(action: { disclaimerChecked.toggle() }) {
                HStack(spacing: 10) {
                    Image(systemName: disclaimerChecked ? "checkmark.square.fill" : "square")
                        .font(.title3)
                        .foregroundColor(disclaimerChecked ? .yellow : .white.opacity(0.4))
                    Text("I understand this game involves tilting my laptop lid and I accept\nall responsibility for any damage to my hardware or dignity.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.leading)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 40)

            Button(action: { disclaimerAccepted = true }) {
                Text("LET'S GO")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(disclaimerChecked ? .black : .white.opacity(0.3))
                    .frame(width: 200)
                    .padding(.vertical, 10)
                    .background(disclaimerChecked
                        ? AnyShapeStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing))
                        : AnyShapeStyle(Color.white.opacity(0.08)))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(!disclaimerChecked)

            Spacer()
        }
    }

    // MARK: - End Screen

    private func endScreen(time: Double) -> some View {
        let pulse = 1.0 + 0.04 * sin(time * 2)
        return VStack(spacing: 14) {
            Spacer()
            Text(gameState.grade)
                .font(.system(size: 72, weight: .black, design: .rounded))
                .foregroundColor(gameState.gradeColor).scaleEffect(pulse)
                .shadow(color: gameState.gradeColor.opacity(0.4), radius: 16)
            Text(gameState.trackName).font(.title3).foregroundColor(.white.opacity(0.5))
            Text("\(gameState.score)")
                .font(.system(size: 32, weight: .black, design: .rounded)).foregroundColor(.white)

            HStack(spacing: 20) {
                statBadge("Perfect", count: gameState.notesPerfect, color: HitAccuracy.perfect.color)
                statBadge("Good", count: gameState.notesGood, color: HitAccuracy.good.color)
                statBadge("OK", count: gameState.notesOK, color: HitAccuracy.ok.color)
                statBadge("Missed", count: max(0, gameState.notesMissed), color: HitAccuracy.miss.color)
            }

            HStack(spacing: 28) {
                VStack(spacing: 2) {
                    Text("Max Combo").font(.caption).foregroundColor(.white.opacity(0.4))
                    Text("\(gameState.maxCombo)x").font(.title3.bold()).foregroundColor(.white)
                }
                VStack(spacing: 2) {
                    Text("Notes Hit").font(.caption).foregroundColor(.white.opacity(0.4))
                    Text("\(gameState.noteResults.count)/\(gameState.notesTotal)").font(.title3.bold()).foregroundColor(.white)
                }
            }

            Text("Click to return to menu").font(.caption).foregroundColor(.yellow.opacity(0.6)).padding(.top, 6)
            Spacer()
        }
    }

    private func statBadge(_ label: String, count: Int, color: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(count)").font(.system(size: 20, weight: .black, design: .rounded)).foregroundColor(color)
            Text(label).font(.system(size: 9, weight: .medium)).foregroundColor(.white.opacity(0.45))
        }
        .frame(width: 56)
    }
}
