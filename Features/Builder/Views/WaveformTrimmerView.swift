import SwiftUI

struct WaveformTrimmerView: View {
    let samples: [Float]
    let duration: TimeInterval
    @Binding var startTime: TimeInterval
    @Binding var endTime: TimeInterval
    var playheadTime: TimeInterval?
    var onSeek: ((TimeInterval) -> Void)?

    private let handleWidth: CGFloat = 14
    private let trimColor = Color(red: 1.0, green: 0.82, blue: 0.0)
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
                Color.black

                // Waveform bars
                waveformCanvas(startFrac: Double(sf), endFrac: Double(ef))

                // Dimmed region — left
                Rectangle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: max(leftX, 0))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                // Dimmed region — right
                Rectangle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: max(w - rightX, 0))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)

                // Top border
                trimBorder(leftX: leftX, rightX: rightX, height: h, top: true)

                // Bottom border
                trimBorder(leftX: leftX, rightX: rightX, height: h, top: false)

                // Playhead overlay — additive only; keep prior trim ribbon/handles intact.
                if let playheadTime, duration > 0 {
                    let px = CGFloat(max(0, min(playheadTime / duration, 1))) * w
                    ZStack(alignment: .top) {
                        Rectangle()
                            .fill(Color.white.opacity(0.88))
                            .frame(width: 2, height: h)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 7, height: 7)
                            .offset(y: 2)
                    }
                    .shadow(color: .white.opacity(0.45), radius: 3)
                    .position(x: px, y: h / 2)
                    .allowsHitTesting(false)
                }

                // Left handle
                handle(isLeft: true, height: h)
                    .position(x: leftX, y: h / 2)
                    .gesture(
                        DragGesture(coordinateSpace: .named("trimmer"))
                            .onChanged { value in
                                let maxTime = endTime - minSelection
                                let newTime = Double(value.location.x / w) * duration
                                startTime = max(0, min(newTime, maxTime))
                            }
                    )

                // Right handle
                handle(isLeft: false, height: h)
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
            .onTapGesture(count: 1, coordinateSpace: .named("trimmer")) { location in
                guard let onSeek, duration > 0 else { return }
                onSeek(max(0, min(Double(location.x / w) * duration, duration)))
            }
        }
        .frame(height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Waveform

    private func waveformCanvas(startFrac: Double, endFrac: Double) -> some View {
        Canvas { context, size in
            let count = samples.count
            guard count > 0 else { return }

            let gap: CGFloat = 1.5
            let barW = max((size.width - CGFloat(count - 1) * gap) / CGFloat(count), 1)

            for (i, amp) in samples.enumerated() {
                let x = CGFloat(i) * (barW + gap)
                let center = Double((x + barW / 2) / size.width)
                let inside = center >= startFrac && center <= endFrac

                let barH = max(CGFloat(amp) * size.height * 0.82, 2)
                let y = (size.height - barH) / 2
                let rect = CGRect(x: x, y: y, width: barW, height: barH)

                context.fill(
                    Path(roundedRect: rect, cornerRadius: 1),
                    with: .color(inside ? .white : .white.opacity(0.22))
                )
            }
        }
    }

    // MARK: - Trim frame borders

    private func trimBorder(leftX: CGFloat, rightX: CGFloat, height: CGFloat, top: Bool) -> some View {
        Rectangle()
            .fill(trimColor)
            .frame(width: max(rightX - leftX, 0), height: 3)
            .position(
                x: (leftX + rightX) / 2,
                y: top ? 1.5 : height - 1.5
            )
    }

    // MARK: - Handles

    private func handle(isLeft: Bool, height: CGFloat) -> some View {
        ZStack {
            // Wider invisible hit target
            Color.clear
                .frame(width: handleWidth + 24, height: height)
                .contentShape(Rectangle())

            // Visible handle
            UnevenRoundedRectangle(
                topLeadingRadius: isLeft ? 6 : 0,
                bottomLeadingRadius: isLeft ? 6 : 0,
                bottomTrailingRadius: isLeft ? 0 : 6,
                topTrailingRadius: isLeft ? 0 : 6
            )
            .fill(trimColor)
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

    var body: some View {
        HStack {
            Text(Formatters.clock(startTime))
            Spacer()
            Text("Duration: \(Formatters.clock(endTime - startTime))")
            Spacer()
            Text(Formatters.clock(endTime))
        }
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }
}
