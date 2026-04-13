import SwiftUI

struct HomeView: View {
    let session: PrototypeSession
    var switchTab: ((Int) -> Void)? = nil

    @State private var currentTime = Date()
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ZStack {
                PPColors.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        greetingHeader
                        heroCard
                        if session.mix != nil {
                            quickActions
                            statsRow
                            sessionsOverview
                        } else {
                            getStartedCard
                        }
                        infoCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 6) {
                        Image(systemName: "music.mic.circle.fill")
                            .foregroundStyle(PPColors.accentYellow)
                        Text("PRACTICE PLAYER")
                            .font(PPFonts.caption(12))
                            .tracking(2)
                            .foregroundStyle(PPColors.textTertiary)
                    }
                }
            }
            .onReceive(timer) { currentTime = $0 }
        }
    }

    // MARK: - Greeting

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greeting)
                .font(PPFonts.hero(32))
                .foregroundStyle(PPColors.textPrimary)

            Text(dateString)
                .font(PPFonts.mono(14))
                .foregroundStyle(PPColors.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: currentTime)
        switch hour {
        case 5..<12: return "Good Morning"
        case 12..<17: return "Good Afternoon"
        case 17..<21: return "Good Evening"
        default: return "Late Night Grind"
        }
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: currentTime)
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [PPColors.accentYellow, PPColors.accentOrange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)

                    Image(systemName: "music.mic")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.black)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.teamName)
                        .font(PPFonts.hero(28))
                        .foregroundStyle(PPColors.textPrimary)

                    if let mix = session.mix {
                        HStack(spacing: 8) {
                            Text(mix.displayName)
                                .lineLimit(1)
                            Text("•")
                            Text(Formatters.clock(mix.duration))
                        }
                        .font(PPFonts.mono())
                        .foregroundStyle(PPColors.textSecondary)
                    } else {
                        Text("No mix imported")
                            .font(PPFonts.mono())
                            .foregroundStyle(PPColors.textTertiary)
                    }
                }

                Spacer()
            }
        }
        .ppCard()
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        HStack(spacing: 12) {
            Button { switchTab?(1) } label: {
                QuickActionCard(
                    icon: "slider.horizontal.3",
                    title: "Edit",
                    subtitle: "Build tab",
                    color: PPColors.accentYellow
                )
            }.buttonStyle(.plain)

            Button { switchTab?(2) } label: {
                QuickActionCard(
                    icon: "play.circle.fill",
                    title: "Practice",
                    subtitle: "Live tab",
                    color: PPColors.success
                )
            }.buttonStyle(.plain)

            QuickActionCard(
                icon: "clock.arrow.circlepath",
                title: "History",
                subtitle: "Coming soon",
                color: PPColors.textTertiary
            )
        }
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 12) {
            statPill(value: "\(session.sections.count)", label: "Sections", icon: "scissors")
            statPill(value: "\(session.blocks.count)", label: "Blocks", icon: "square.stack.3d.up")
            statPill(value: Formatters.clock(session.totalEstimatedDuration), label: "Est. Time", icon: "clock")
        }
    }

    private func statPill(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(PPColors.accentYellow)

            Text(value)
                .font(PPFonts.monoLarge(22))
                .foregroundStyle(PPColors.textPrimary)

            Text(label.uppercased())
                .font(PPFonts.caption(10))
                .tracking(0.8)
                .foregroundStyle(PPColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .ppCard()
    }

    // MARK: - Sessions Overview

    private var sessionsOverview: some View {
        VStack(spacing: 12) {
            PPSectionHeader(title: "Practice Blocks")

            VStack(spacing: 0) {
                ForEach(Array(session.blocks.enumerated()), id: \.element.id) { index, block in
                    if index > 0 {
                        Divider()
                            .background(PPColors.cardBorder)
                            .padding(.leading, 52)
                    }

                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(block.section.type.accentColor.opacity(0.15))
                                .frame(width: 36, height: 36)

                            Text("\(index + 1)")
                                .font(PPFonts.mono(13))
                                .foregroundStyle(block.section.type.accentColor)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(block.title)
                                .font(PPFonts.headline(15))
                                .foregroundStyle(PPColors.textPrimary)

                            HStack(spacing: 8) {
                                Text("\(block.reps)× reps")
                                Text("•")
                                Text(block.section.name)
                                Text("•")
                                Text(Formatters.clock(block.estimatedDuration))
                            }
                            .font(PPFonts.mono(11))
                            .foregroundStyle(PPColors.textTertiary)
                        }

                        Spacer()

                        if block.metronomeEnabled {
                            Image(systemName: "metronome.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(PPColors.accentOrange)
                        }

                        Image(systemName: block.restartMode == .automatic ? "repeat" : "hand.tap")
                            .font(.system(size: 12))
                            .foregroundStyle(PPColors.textTertiary)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(PPColors.card))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Get Started

    private var getStartedCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(PPColors.accentYellow)
                .padding(.top, 8)

            Text("Ready to build your practice?")
                .font(PPFonts.title(20))
                .foregroundStyle(PPColors.textPrimary)

            Text("Import your team's competition mix in the Build tab, mark sections, and create practice blocks with reps and rest windows.")
                .font(PPFonts.body(14))
                .foregroundStyle(PPColors.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            HStack(spacing: 16) {
                stepIndicator(number: "1", text: "Import mix")
                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundStyle(PPColors.textTertiary)
                stepIndicator(number: "2", text: "Mark sections")
                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundStyle(PPColors.textTertiary)
                stepIndicator(number: "3", text: "Practice")
            }
            .padding(.top, 4)
        }
        .ppCard()
    }

    private func stepIndicator(number: String, text: String) -> some View {
        VStack(spacing: 4) {
            Circle()
                .fill(PPColors.accentYellow)
                .frame(width: 24, height: 24)
                .overlay {
                    Text(number)
                        .font(PPFonts.caption(12))
                        .fontWeight(.bold)
                        .foregroundStyle(.black)
                }

            Text(text)
                .font(PPFonts.caption(10))
                .foregroundStyle(PPColors.textSecondary)
        }
    }

    // MARK: - Info Card

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(PPColors.accentYellow)
                Text("ABOUT")
                    .font(PPFonts.caption(11))
                    .tracking(1.5)
                    .foregroundStyle(PPColors.textTertiary)
            }

            Text("Run practice from your team's actual mix with automatic section repeats, timed breaks, lead-ins, and sync support.")
                .font(PPFonts.body(14))
                .foregroundStyle(PPColors.textSecondary)
                .lineSpacing(4)
        }
        .ppCard()
    }
}

// MARK: - Quick Action Card

private struct QuickActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(color)

            Text(title)
                .font(PPFonts.headline(13))
                .foregroundStyle(PPColors.textPrimary)

            Text(subtitle)
                .font(PPFonts.caption(10))
                .foregroundStyle(PPColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .ppCard()
    }
}
