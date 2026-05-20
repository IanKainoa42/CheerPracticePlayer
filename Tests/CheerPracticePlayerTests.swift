import XCTest
@testable import CheerPracticePlayer

@MainActor
final class CheerPracticePlayerTests: XCTestCase {
    func testLiveSessionControllerPlayCurrentBlock_StartsAudioAtSectionStart() {
        let audioPlayer = FakeAudioPlayer()
        let controller = LiveSessionController(
            session: PrototypeSession.sample,
            audioPlayer: audioPlayer
        )

        controller.playCurrentBlock()

        XCTAssertEqual(audioPlayer.loadedURL?.path, PrototypeSession.sample.mix?.localPath)
        XCTAssertEqual(audioPlayer.seekTimes, [PrototypeSession.sample.blocks[0].section.startTime])
        XCTAssertEqual(audioPlayer.playCallCount, 1)
        XCTAssertEqual(controller.runner.phase, .playing)
    }

    func testLiveSessionControllerRestartBlock_SeeksAndPlaysCurrentSection() {
        let audioPlayer = FakeAudioPlayer()
        let controller = LiveSessionController(
            session: PrototypeSession.sample,
            audioPlayer: audioPlayer
        )

        controller.restartBlock()

        XCTAssertEqual(audioPlayer.seekTimes, [PrototypeSession.sample.blocks[0].section.startTime])
        XCTAssertEqual(audioPlayer.playCallCount, 1)
        XCTAssertEqual(controller.runner.currentRep, 1)
    }

    func testLiveSessionControllerSkipBlock_AdvancesAndPlaysNextSection() {
        let audioPlayer = FakeAudioPlayer()
        let controller = LiveSessionController(
            session: PrototypeSession.sample,
            audioPlayer: audioPlayer
        )

        controller.skipBlock()

        XCTAssertEqual(controller.runner.currentBlockIndex, 1)
        XCTAssertEqual(audioPlayer.seekTimes, [PrototypeSession.sample.blocks[1].section.startTime])
        XCTAssertEqual(audioPlayer.playCallCount, 1)
    }

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

    func testBlockEstimatedDuration_IncludesRepsAndRest() {
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
            restartMode: .automatic
        )

        // 5 reps * 30s section + 4 rest windows * 45s = 150 + 180 = 330
        XCTAssertEqual(block.estimatedDuration, 330, accuracy: 0.001)
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

    func testRunner_IntraBlockBreak_IncrementsRepCorrectly() {
        var runner = SessionRunnerState(template: PrototypeSession.sample)
        runner.start()
        
        XCTAssertEqual(runner.currentBlockIndex, 0)
        XCTAssertEqual(runner.currentRep, 1)
        XCTAssertEqual(runner.phase, .playing)
        
        // Finish Rep 1. Should immediately increment currentRep to 2 and transition to .breakCountdown
        runner.finishRep()
        XCTAssertEqual(runner.currentBlockIndex, 0)
        XCTAssertEqual(runner.currentRep, 2)
        if case .breakCountdown(let remaining) = runner.phase {
            XCTAssertEqual(remaining, 45)
        } else {
            XCTFail("Phase should be breakCountdown")
        }
        
        // Completing the break should change phase to .playing and currentRep remains 2
        runner.completeBreak()
        XCTAssertEqual(runner.currentBlockIndex, 0)
        XCTAssertEqual(runner.currentRep, 2)
        XCTAssertEqual(runner.phase, .playing)
    }

    func testRunner_InterBlockBreak_PreservesFirstRep() {
        var runner = SessionRunnerState(template: PrototypeSession.sample)
        runner.start()
        
        // Finish all reps of first block (reps = 5)
        for i in 1...4 {
            XCTAssertEqual(runner.currentRep, i)
            runner.finishRep() // enters break countdown
            runner.completeBreak() // goes to playing next rep
        }
        
        // Now on Rep 5 (final rep of Block 0)
        XCTAssertEqual(runner.currentRep, 5)
        XCTAssertEqual(runner.currentBlockIndex, 0)
        
        // Finish Rep 5. Should advance to Block 1, set currentRep = 1, and since block 1 has restSeconds = 60, it should be in .breakCountdown.
        runner.finishRep()
        
        XCTAssertEqual(runner.currentBlockIndex, 1)
        XCTAssertEqual(runner.currentRep, 1) // Crucial check! Should be 1, not 2!
        if case .breakCountdown(let remaining) = runner.phase {
            XCTAssertEqual(remaining, 60)
        } else {
            XCTFail("Phase should be breakCountdown")
        }
        
        // Let's tick the countdown. Ticking it down to 1 remaining.
        for _ in 1..<60 {
            let keepTicking = runner.tickCountdown()
            XCTAssertTrue(keepTicking)
            XCTAssertEqual(runner.currentRep, 1) // Rep must stay 1 during countdown
        }
        
        // Final tick should return false and transition to playing, and currentRep remains 1
        let keepTicking = runner.tickCountdown()
        XCTAssertFalse(keepTicking)
        XCTAssertEqual(runner.currentBlockIndex, 1)
        XCTAssertEqual(runner.currentRep, 1) // Crucial! Still 1! No skipped first rep!
        XCTAssertEqual(runner.phase, .playing)
    }

    func testRunner_RepsCompletedAndProgress_AccurateDuringRest() {
        var runner = SessionRunnerState(template: PrototypeSession.sample)
        runner.start()
        
        // Finish Rep 1. Under the new approach, currentRep is 2 during the rest.
        runner.finishRep()
        
        // Total completed reps should be 1 (because Rep 1 is done, and we are resting before Rep 2).
        XCTAssertEqual(runner.totalRepsCompleted, 1)
        
        // Verify sessionProgress includes that completed rep's weight.
        // Block 0 reps = 5, totalBlocks = 3.
        XCTAssertEqual(runner.sessionProgress, 0.2 / 3.0, accuracy: 0.0001)
    }

    func testLiveSessionController_ResumeAtOrAfterEnd_FinishesImmediately() {
        let audioPlayer = FakeAudioPlayer()
        let controller = LiveSessionController(
            session: PrototypeSession.sample,
            audioPlayer: audioPlayer
        )
        
        controller.playCurrentBlock()
        
        // Pause the controller
        controller.pausePlayback()
        
        // Set currentTime close to section end
        let section = PrototypeSession.sample.blocks[0].section
        audioPlayer.currentTime = section.endTime - 0.005 // remaining < 0.01s
        
        controller.resumePlayback()
        
        // Should immediately transition to rest or next state (finish playback)
        XCTAssertEqual(controller.runner.currentRep, 2)
        XCTAssertEqual(audioPlayer.playCallCount, 1) // Not called again on resume!
    }

    func testLiveSessionController_PausePlayback_InvalidatesTimersAndPausesPlayer() {
        let audioPlayer = FakeAudioPlayer()
        let controller = LiveSessionController(
            session: PrototypeSession.sample,
            audioPlayer: audioPlayer
        )
        
        controller.playCurrentBlock()
        
        XCTAssertFalse(controller.isPaused)
        XCTAssertNotNil(controller.playbackEndTimer)
        
        controller.pausePlayback()
        
        XCTAssertTrue(controller.isPaused)
        XCTAssertNil(controller.playbackEndTimer)
        XCTAssertEqual(audioPlayer.pauseCallCount, 1)
    }
}

private final class FakeAudioPlayer: AudioPlaybackControlling {
    var loadedURL: URL?
    var seekTimes: [TimeInterval] = []
    var playCallCount = 0
    var pauseCallCount = 0
    var currentTime: TimeInterval = 0
    var rate: Float = 1.0

    func load(url: URL) throws {
        loadedURL = url
    }

    func playSegment(startTime: TimeInterval, endTime: TimeInterval) {
        seekTimes.append(startTime)
        playCallCount += 1
    }

    func resumeUntil(remainingDuration: TimeInterval) {
        playCallCount += 1
    }

    func pause() {
        pauseCallCount += 1
    }

    func seek(to time: TimeInterval) {
        currentTime = time
    }
}
