import XCTest
@testable import CheerPracticePlayer

final class CheerPracticePlayerTests: XCTestCase {
    func testSectionClampedToMixDuration_KeepsRangeValid() {
        let section = PracticeSection(
            id: UUID(),
            name: "Dance",
            type: .dance,
            startTime: -12,
            endTime: 250
        )

        let clamped = section.clamped(to: 120)

        XCTAssertEqual(clamped.startTime, 0, accuracy: 0.001)
        XCTAssertEqual(clamped.endTime, 120, accuracy: 0.001)
    }

    func testSessionUpsertSection_UpdatesSectionLibraryAndExistingBlocks() {
        var session = PrototypeSession.sample
        var updatedSection = session.sections[0]
        updatedSection.name = "Updated Tumble"
        updatedSection.startTime = 80
        updatedSection.endTime = 104

        session.upsertSection(updatedSection)

        XCTAssertEqual(session.sections[0].name, "Updated Tumble")
        XCTAssertEqual(session.blocks[0].section.name, "Updated Tumble")
        XCTAssertEqual(session.blocks[0].section.startTime, 80, accuracy: 0.001)
        XCTAssertEqual(session.blocks[0].section.endTime, 104, accuracy: 0.001)
    }

    func testSessionRemoveSection_RemovesDependentBlocks() {
        var session = PrototypeSession.sample
        let removedID = session.sections[1].id

        session.removeSection(id: removedID)

        XCTAssertFalse(session.sections.contains(where: { $0.id == removedID }))
        XCTAssertFalse(session.blocks.contains(where: { $0.section.id == removedID }))
    }

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
