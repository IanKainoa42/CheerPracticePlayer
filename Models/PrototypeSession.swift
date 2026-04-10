import Foundation

struct PrototypeSession: Identifiable, Equatable {
    let id: UUID
    var teamName: String
    var mixName: String
    var blocks: [PracticeBlock]

    var totalEstimatedDuration: TimeInterval {
        blocks.reduce(0) { $0 + $1.estimatedDuration }
    }

    static let sample: PrototypeSession = {
        let tumble = PracticeSection(
            id: UUID(),
            name: "Tumble Section",
            type: .runningTumbling,
            startTime: 72,
            endTime: 98
        )
        let pyramid = PracticeSection(
            id: UUID(),
            name: "Pyramid",
            type: .pyramid,
            startTime: 110,
            endTime: 145
        )
        let fullOut = PracticeSection(
            id: UUID(),
            name: "Full Out",
            type: .fullOut,
            startTime: 0,
            endTime: 155
        )

        return PrototypeSession(
            id: UUID(),
            teamName: "CFSD Blackout",
            mixName: "Blackout Worlds Mix",
            blocks: [
                PracticeBlock(
                    id: UUID(),
                    title: "5x Tumbling",
                    section: tumble,
                    reps: 5,
                    restSeconds: 45,
                    leadInSeconds: 8,
                    restartMode: .automatic,
                    metronomeEnabled: true
                ),
                PracticeBlock(
                    id: UUID(),
                    title: "4x Pyramid",
                    section: pyramid,
                    reps: 4,
                    restSeconds: 60,
                    leadInSeconds: 8,
                    restartMode: .manual,
                    metronomeEnabled: false
                ),
                PracticeBlock(
                    id: UUID(),
                    title: "2x Full Out",
                    section: fullOut,
                    reps: 2,
                    restSeconds: 120,
                    leadInSeconds: 16,
                    restartMode: .automatic,
                    metronomeEnabled: false
                )
            ]
        )
    }()
}
