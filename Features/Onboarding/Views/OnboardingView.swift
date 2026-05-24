import SwiftUI

struct OnboardingView: View {
    let onStart: () -> Void
    let onSkip: () -> Void

    @State private var selectedStep = 0

    private let steps = OnboardingStep.allCases

    var body: some View {
        ZStack {
            PPColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text("PracticeMix")
                        .font(PPFonts.headline(17))
                        .foregroundStyle(PPColors.textPrimary)

                    Spacer()

                    Button("Skip", action: onSkip)
                    .font(PPFonts.caption(12))
                    .textCase(.uppercase)
                    .tracking(1.0)
                    .foregroundStyle(PPColors.textSecondary)
                    .accessibilityLabel("Skip onboarding")
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)

                TabView(selection: $selectedStep) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        OnboardingStepView(step: step, stepNumber: index + 1, totalSteps: steps.count)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                VStack(spacing: 18) {
                    HStack(spacing: 8) {
                        ForEach(steps.indices, id: \.self) { index in
                            Capsule()
                                .fill(index == selectedStep ? PPColors.accentYellow : PPColors.cardBorder)
                                .frame(width: index == selectedStep ? 28 : 8, height: 8)
                                .animation(.spring(response: 0.28, dampingFraction: 0.8), value: selectedStep)
                        }
                    }
                    .accessibilityHidden(true)

                    PPPrimaryButton(primaryButtonTitle, icon: primaryButtonIcon) {
                        if selectedStep == steps.count - 1 {
                            onStart()
                        } else {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                selectedStep += 1
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .background(
                    LinearGradient(
                        colors: [PPColors.background.opacity(0), PPColors.background],
                        startPoint: .top,
                        endPoint: .center
                    )
                    .allowsHitTesting(false)
                )
            }
        }
        .preferredColorScheme(.dark)
    }

    private var primaryButtonTitle: String {
        selectedStep == steps.count - 1 ? "Start With a Mix" : "Next"
    }

    private var primaryButtonIcon: String {
        selectedStep == steps.count - 1 ? "square.and.arrow.down" : "arrow.right"
    }
}

private struct OnboardingStepView: View {
    let step: OnboardingStep
    let stepNumber: Int
    let totalSteps: Int

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 26) {
                    Spacer(minLength: 10)

                    ZStack {
                        Circle()
                            .fill(step.tint.opacity(0.14))
                            .frame(width: min(proxy.size.width * 0.62, 260), height: min(proxy.size.width * 0.62, 260))

                        Circle()
                            .strokeBorder(step.tint.opacity(0.35), lineWidth: 1)
                            .frame(width: min(proxy.size.width * 0.54, 230), height: min(proxy.size.width * 0.54, 230))

                        Image(systemName: step.symbolName)
                            .font(.system(size: min(proxy.size.width * 0.18, 76), weight: .black))
                            .foregroundStyle(step.tint)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 18)

                    VStack(spacing: 14) {
                        Text("STEP \(stepNumber) OF \(totalSteps)")
                            .font(PPFonts.caption(11))
                            .tracking(1.4)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(step.tint))

                        Text(step.title)
                            .font(PPFonts.hero(32))
                            .foregroundStyle(PPColors.textPrimary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .minimumScaleFactor(0.82)

                        Text(step.body)
                            .font(PPFonts.body(16))
                            .foregroundStyle(PPColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.horizontal, 10)
                    }

                    VStack(spacing: 10) {
                        ForEach(step.coachNotes, id: \.self) { note in
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(step.tint)
                                    .frame(width: 24)

                                Text(note)
                                    .font(PPFonts.body(14))
                                    .foregroundStyle(PPColors.textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(PPColors.card)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(PPColors.cardBorder, lineWidth: 1)
                            )
                        }
                    }
                    .padding(.top, 4)

                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 20)
                .frame(minHeight: proxy.size.height)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private enum OnboardingStep: CaseIterable, Identifiable {
    case importMix
    case markSections
    case runPractice

    var id: Self { self }

    var symbolName: String {
        switch self {
        case .importMix:
            return "music.note.list"
        case .markSections:
            return "waveform.and.scissors"
        case .runPractice:
            return "play.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .importMix:
            return PPColors.accentYellow
        case .markSections:
            return PPColors.accentOrange
        case .runPractice:
            return PPColors.success
        }
    }

    var title: String {
        switch self {
        case .importMix:
            return "BRING IN YOUR MIX"
        case .markSections:
            return "MARK THE PARTS YOU DRILL"
        case .runPractice:
            return "RUN REPS WITHOUT BABYSITTING AUDIO"
        }
    }

    var body: String {
        switch self {
        case .importMix:
            return "Start by importing the routine music you use at practice."
        case .markSections:
            return "Trim stunts, tumbling, pyramid, dance, or a full-out section once and keep it ready."
        case .runPractice:
            return "Build blocks with reps, rest, and countdowns so the next section is ready when the team is."
        }
    }

    var coachNotes: [String] {
        switch self {
        case .importMix:
            return ["Saved mixes stay in your Library", "One tap gets you back to the same routine"]
        case .markSections:
            return ["Drag handles for fast in and out points", "Preview before saving a section"]
        case .runPractice:
            return ["Large controls are built for the gym floor", "Tap a block to jump when practice changes"]
        }
    }
}
