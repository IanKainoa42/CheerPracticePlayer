import SwiftUI

struct WaveformTrimmerView: View {
    let samples: [Float]
    let duration: TimeInterval
    @Binding var startTime: TimeInterval
    @Binding var endTime: TimeInterval
    var playheadTime: TimeInterval?
    var onSeek: ((TimeInterval) -> Void)?

    private let handleWidth: CGFloat = 16
    private let startColor = PPColors.accentYellow
    private let endColor = PPColors.accentOrange
    private let minSelection: TimeInterval = 0.5

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let startFraction = duration > 0 ? CGFloat(startTime / duration) : 0
            let endFraction = duration > 0 ? CGFloat(endTime / duration) : 1
            let leftX = startFraction * width
            let rightX = endFraction * width

            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(white: 0.06))

                // Waveform bars
                waveformCanvas(startFrac: Double(startFraction), endFrac: Double(endFraction))

                // Dimmed region — left
                Rectangle()
                    .fill(Color.black.opacity(0.6))
                    .frame(width: max(leftX, 0))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                // Dimmed region — right
                Rectangle()
                    .fill(Color.black.opacity(0.6))
                    .frame(width: max(width - rightX, 0))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)

                // Top border
                trimBorder(leftX: leftX, rightX: rightX, height: height, top: true)

                // Bottom border
                trimBorder(leftX: leftX, rightX: rightX, height: height, top: false)

                // Playhead overlay — sits above waveform, below handles
                if let playheadTime, duration > 0 {
                    let playheadX = CGFloat(max(0, min(playheadTime / duration, 1))) * width
                    ZStack(alignment: .top) {
                        Rectangle()
                            .fill(Color.white.opacity(0.88))
                            .frame(width: 2, height: height)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 7, height: 7)
                            .offset(y: 2)
                    }
                    .shadow(color: .white.opacity(0.45), radius: 3)
                    .position(x: playheadX, y: height / 2)
                    .allowsHitTesting(false)
                }

                // Left handle (Start)
                handle(isLeft: true, height: height)
                    .position(x: leftX, y: height / 2)
                    .gesture(
                        DragGesture(coordinateSpace: .named("trimmer"))
                            .onChanged { value in
                                let maxTime = endTime - minSelection
                                let newTime = Double(value.location.x / width) * duration
                                startTime = max(0, min(newTime, maxTime))
                            }
                    )

                // Right handle (End)
                handle(isLeft: false, height: height)
                    .position(x: rightX, y: height / 2)
                    .gesture(
                        DragGesture(coordinateSpace: .named("trimmer"))
                            .onChanged { value in
                                let minTime = startTime + minSelection
                                let newTime = Double(value.location.x / width) * duration
                                endTime = min(duration, max(newTime, minTime))
                            }
                    )
            }
            .coordinateSpace(name: "trimmer")
            .onTapGesture(count: 1, coordinateSpace: .named("trimmer")) { location in
                guard let onSeek, duration > 0 else { return }
                onSeek(max(0, min(Double(location.x / width) * duration, duration)))
            }
        }
        .frame(height: 88)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Waveform

    private func waveformCanvas(startFrac: Double, endFrac: Double) -> some View {
        Canvas { context, size in
            let count = samples.count
            guard count > 0 else { return }

            let gap: CGFloat = 2
            let barWidth = max((size.width - CGFloat(count - 1) * gap) / CGFloat(count), 1.5)

            for (index, amplitude) in samples.enumerated() {
                let xPosition = CGFloat(index) * (barWidth + gap)
                let centerFraction = Double((xPosition + barWidth / 2) / size.width)
                let isInsideSelection = centerFraction >= startFrac && centerFraction <= endFrac

                let barHeight = max(CGFloat(amplitude) * size.height * 0.78, 2)
                let yPosition = (size.height - barHeight) / 2
                let rect = CGRect(x: xPosition, y: yPosition, width: barWidth, height: barHeight)

                let color: Color
                if isInsideSelection {
                    // Gradient from yellow to orange across the selection
                    let threshold = (centerFraction - startFrac) / max(endFrac - startFrac, 0.001)
                    let redVal = 1.0
                    let greenVal = 0.92 - threshold * 0.50   // yellow -> orange
                    let blueVal = 0.23 - threshold * 0.02
                    color = Color(red: redVal, green: greenVal, blue: blueVal).opacity(0.9)
                } else {
                    color = .white.opacity(0.15)
                }

                context.fill(
                    Path(roundedRect: rect, cornerRadius: 1.5),
                    with: .color(color)
                )
            }
        }
    }

    // MARK: - Trim frame borders

    private func trimBorder(leftX: CGFloat, rightX: CGFloat, height: CGFloat, top: Bool) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [startColor, endColor],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: max(rightX - leftX, 0), height: 3)
            .position(
                x: (leftX + rightX) / 2,
                y: top ? 1.5 : height - 1.5
            )
    }

    // MARK: - Handles

    private func handle(isLeft: Bool, height: CGFloat) -> some View {
        let color = isLeft ? startColor : endColor
        
        return ZStack {
            // Wider invisible hit target
            Color.clear
                .frame(width: handleWidth + 28, height: height)
                .contentShape(Rectangle())

            // Glow effect
            UnevenRoundedRectangle(
                topLeadingRadius: isLeft ? 6 : 0,
                bottomLeadingRadius: isLeft ? 6 : 0,
                bottomTrailingRadius: isLeft ? 0 : 6,
                topTrailingRadius: isLeft ? 0 : 6
            )
            .fill(color.opacity(0.3))
            .frame(width: handleWidth + 6, height: height)
            .blur(radius: 4)

            // Visible handle
            UnevenRoundedRectangle(
                topLeadingRadius: isLeft ? 6 : 0,
                bottomLeadingRadius: isLeft ? 6 : 0,
                bottomTrailingRadius: isLeft ? 0 : 6,
                topTrailingRadius: isLeft ? 0 : 6
            )
            .fill(color)
            .frame(width: handleWidth, height: height)
            .overlay {
                Image(systemName: isLeft ? "chevron.compact.left" : "chevron.compact.right")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.black.opacity(0.5))
            }
        }
    }
}

// MARK: - Time labels row (displayed below the trimmer)

struct TrimTimeLabelsView: View {
    let startTime: TimeInterval
    let endTime: TimeInterval
    /// When provided AND larger than `endTime`, render a faint "of M:SS" suffix
    /// next to the end label so the user can see the trimmer can be dragged further
    /// to cover the remainder of the mix (QA M1).
    var mixDuration: TimeInterval? = nil

    private var showsMaxHint: Bool {
        guard let d = mixDuration else { return false }
        return d > endTime + 0.5
    }

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                Circle().fill(PPColors.accentYellow).frame(width: 6, height: 6)
                Text(Formatters.clock(startTime))
            }
            Spacer()
            Text("Duration: \(Formatters.clock(endTime - startTime))")
                .foregroundStyle(PPColors.textPrimary)
            Spacer()
            HStack(spacing: 4) {
                Text(Formatters.clock(endTime))
                if showsMaxHint, let d = mixDuration {
                    Text("/ \(Formatters.clock(d))")
                        .foregroundStyle(PPColors.textTertiary)
                }
                Circle().fill(PPColors.accentOrange).frame(width: 6, height: 6)
            }
        }
        .font(PPFonts.mono())
        .foregroundStyle(PPColors.textSecondary)
    }
}
