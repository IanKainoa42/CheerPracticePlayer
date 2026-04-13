import SwiftUI

struct WaveformTrimmerView: View {
    let samples: [Float]
    let duration: TimeInterval
    @Binding var startTime: TimeInterval
    @Binding var endTime: TimeInterval

    private let handleWidth: CGFloat = 16
    private let startColor = PPColors.accentYellow
    private let endColor = PPColors.accentOrange
    private let minSelection: TimeInterval = 0.5

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let sf = duration > 0 ? CGFloat(startTime / duration) : 0
            let ef = duration > 0 ? CGFloat(endTime / duration) : 1
            let leftX = sf * w
            let rightX = ef * w

            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(white: 0.06))

                // Waveform bars
                waveformCanvas(startFrac: Double(sf), endFrac: Double(ef))

                // Dimmed region — left
                Rectangle()
                    .fill(Color.black.opacity(0.6))
                    .frame(width: max(leftX, 0))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                // Dimmed region — right
                Rectangle()
                    .fill(Color.black.opacity(0.6))
                    .frame(width: max(w - rightX, 0))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)

                // Top border
                trimBorder(leftX: leftX, rightX: rightX, height: h, top: true)

                // Bottom border
                trimBorder(leftX: leftX, rightX: rightX, height: h, top: false)

                // Left handle (Start)
                handle(isStart: true, height: h)
                    .position(x: leftX, y: h / 2)
                    .gesture(
                        DragGesture(coordinateSpace: .named("trimmer"))
                            .onChanged { value in
                                let maxTime = endTime - minSelection
                                let newTime = Double(value.location.x / w) * duration
                                startTime = max(0, min(newTime, maxTime))
                            }
                    )

                // Right handle (End)
                handle(isStart: false, height: h)
                    .position(x: rightX, y: h / 2)
                    .gesture(
                        DragGesture(coordinateSpace: .named("trimmer"))
                            .onChanged { value in
                                let minTime = startTime + minSelection
                                let newTime = Double(value.location.x / w) * duration
                                endTime = min(duration, max(newTime, minTime))
                            }
                    )
            }
            .coordinateSpace(name: "trimmer")
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
            let barW = max((size.width - CGFloat(count - 1) * gap) / CGFloat(count), 1.5)

            for (i, amp) in samples.enumerated() {
                let x = CGFloat(i) * (barW + gap)
                let center = Double((x + barW / 2) / size.width)
                let inside = center >= startFrac && center <= endFrac

                let barH = max(CGFloat(amp) * size.height * 0.78, 2)
                let y = (size.height - barH) / 2
                let rect = CGRect(x: x, y: y, width: barW, height: barH)

                let color: Color
                if inside {
                    // Gradient from yellow to orange across the selection
                    let t = (center - startFrac) / max(endFrac - startFrac, 0.001)
                    let r = 1.0
                    let g = 0.92 - t * 0.50   // yellow -> orange
                    let b = 0.23 - t * 0.02
                    color = Color(red: r, green: g, blue: b).opacity(0.9)
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

    private func handle(isStart: Bool, height: CGFloat) -> some View {
        let color = isStart ? startColor : endColor
        let letter = isStart ? "S" : "E"

        return ZStack {
            // Wider invisible hit target
            Color.clear
                .frame(width: handleWidth + 28, height: height)
                .contentShape(Rectangle())

            // Glow effect
            UnevenRoundedRectangle(
                topLeadingRadius: isStart ? 6 : 0,
                bottomLeadingRadius: isStart ? 6 : 0,
                bottomTrailingRadius: isStart ? 0 : 6,
                topTrailingRadius: isStart ? 0 : 6
            )
            .fill(color.opacity(0.3))
            .frame(width: handleWidth + 6, height: height)
            .blur(radius: 4)

            // Visible handle
            UnevenRoundedRectangle(
                topLeadingRadius: isStart ? 6 : 0,
                bottomLeadingRadius: isStart ? 6 : 0,
                bottomTrailingRadius: isStart ? 0 : 6,
                topTrailingRadius: isStart ? 0 : 6
            )
            .fill(color)
            .frame(width: handleWidth, height: height)
            .overlay {
                Text(letter)
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(.black.opacity(0.6))
            }
        }
    }
}

// MARK: - Time labels row (displayed below the trimmer)

struct TrimTimeLabelsView: View {
    let startTime: TimeInterval
    let endTime: TimeInterval

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
                Circle().fill(PPColors.accentOrange).frame(width: 6, height: 6)
            }
        }
        .font(PPFonts.mono())
        .foregroundStyle(PPColors.textSecondary)
    }
}
