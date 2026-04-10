import XCTest
@testable import CheerPracticePlayer

final class CheerPracticePlayerTests: XCTestCase {
    func testBlockEstimatedDuration_IncludesRepsRestAndLeadIn() {
        let section = PracticeSection(
            id: UUID(),
            name: "Tumble",
            type: .runningTumbling,
            startTime: 10,
            endTime: 40
        )
        let block = PracticeBlock(
            id: UUID(),
            title: "Five Tumbling Reps",
            section: section,
            reps: 5,
            restSeconds: 45,
            leadInSeconds: 8,
            restartMode: .automatic,
            metronomeEnabled: true
        )

        XCTAssertEqual(block.estimatedDuration, 370, accuracy: 0.001)
    }

    func testSessionTotalDuration_SumsBlocks() {
        let session = PrototypeSession.sample
        let manualTotal = session.blocks.reduce(0) { $0 + $1.estimatedDuration }

        XCTAssertEqual(session.totalEstimatedDuration, manualTotal, accuracy: 0.001)
    }

    func testRunnerAdvance_MovesToNextBlockAfterFinalRep() {
        var runner = SessionRunnerState(template: PrototypeSession.sample)
        runner.start()

        for _ in 1..<PrototypeSession.sample.blocks[0].reps {
            runner.advance()
        }
        runner.advance()

        XCTAssertEqual(runner.currentBlockIndex, 1)
        XCTAssertEqual(runner.currentRep, 1)
        XCTAssertEqual(runner.phase, .playing)
    }

    func testRunnerSkipBlock_CompletesAtEnd() {
        var runner = SessionRunnerState(template: PrototypeSession.sample)
        runner.skipBlock()
        runner.skipBlock()
        runner.skipBlock()

        XCTAssertEqual(runner.phase, .complete)
    }
}
