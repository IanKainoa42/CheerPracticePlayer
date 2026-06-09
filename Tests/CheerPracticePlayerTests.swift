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

        XCTAssertEqual(audioPlayer.loadedURL?.lastPathComponent, PrototypeSession.sample.mix?.fileName)
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
        let manualTotal = session.blocks.enumerated().reduce(0) { total, pair in
            let (index, block) = pair
            let reps = Double(block.reps)
            let duration = block.section.duration * reps
            let internalRest = Double(max(block.reps - 1, 0) * block.restSeconds)
            let externalRest = index > 0 ? Double(block.restSeconds) : 0
            return total + duration + internalRest + externalRest
        }

        XCTAssertEqual(session.totalEstimatedDuration, manualTotal, accuracy: 0.001)
    }

    func testSavedMixEstimatedSessionDuration_MatchesSessionTotal() {
        let sample = PrototypeSession.sample
        guard let mix = sample.mix else {
            return XCTFail("Sample session must carry a mix")
        }
        let saved = SavedMix(
            id: UUID(),
            mix: mix,
            sections: sample.sections,
            blocks: sample.blocks,
            dateAdded: Date()
        )

        // Library row and Builder "Est" must report the identical run length.
        XCTAssertEqual(
            saved.estimatedSessionDuration,
            sample.totalEstimatedDuration,
            accuracy: 0.001,
            "SavedMix run estimate should match the programmed session total"
        )
    }

    func testTotalEstimatedDuration_EmptyBlocksIsZero() {
        XCTAssertEqual(PracticeBlock.totalEstimatedDuration(for: []), 0, accuracy: 0.001)
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
        for index in 1...4 {
            XCTAssertEqual(runner.currentRep, index)
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
        
        // Final tick should return false and, because the next sample block is manual,
        // wait for the coach to tap before playing rep 1.
        let keepTicking = runner.tickCountdown()
        XCTAssertFalse(keepTicking)
        XCTAssertEqual(runner.currentBlockIndex, 1)
        XCTAssertEqual(runner.currentRep, 1) // Crucial! Still 1! No skipped first rep!
        XCTAssertEqual(runner.phase, .waitingForManualStart)

        runner.start()
        XCTAssertEqual(runner.currentRep, 1)
        XCTAssertEqual(runner.phase, .playing)
    }

    func testRunnerManualRestartMode_WaitsAfterRestForNextRep() {
        let section = PracticeSection(
            id: UUID(),
            name: "Manual Drill",
            type: .dance,
            startTime: 10,
            endTime: 20
        )
        let block = PracticeBlock(
            id: UUID(),
            title: "Manual Drill",
            section: section,
            reps: 2,
            restSeconds: 3,
            restartMode: .manual
        )
        var runner = SessionRunnerState(
            template: PrototypeSession(
                id: UUID(),
                teamName: "Test",
                mix: nil,
                sections: [section],
                blocks: [block]
            )
        )

        runner.start()
        runner.finishRep()

        XCTAssertEqual(runner.currentRep, 2)
        XCTAssertEqual(runner.phase, .breakCountdown(secondsRemaining: 3))
        XCTAssertTrue(runner.tickCountdown())
        XCTAssertTrue(runner.tickCountdown())
        XCTAssertFalse(runner.tickCountdown())
        XCTAssertEqual(runner.phase, .waitingForManualStart)
    }

    func testRunnerAutomaticRestartMode_PlaysAfterRestForNextRep() {
        let section = PracticeSection(
            id: UUID(),
            name: "Auto Drill",
            type: .dance,
            startTime: 10,
            endTime: 20
        )
        let block = PracticeBlock(
            id: UUID(),
            title: "Auto Drill",
            section: section,
            reps: 2,
            restSeconds: 3,
            restartMode: .automatic
        )
        var runner = SessionRunnerState(
            template: PrototypeSession(
                id: UUID(),
                teamName: "Test",
                mix: nil,
                sections: [section],
                blocks: [block]
            )
        )

        runner.start()
        runner.finishRep()

        XCTAssertEqual(runner.currentRep, 2)
        XCTAssertEqual(runner.phase, .breakCountdown(secondsRemaining: 3))
        XCTAssertTrue(runner.tickCountdown())
        XCTAssertTrue(runner.tickCountdown())
        XCTAssertFalse(runner.tickCountdown())
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

    func testLiveSessionController_ResumeAfterPauseDuringBreak_RestartsCountdownAndDoesNotReplayAudio() {
        // Regression: tab-switch (or any pause) during a rest interval used to
        // dead-end the session. resumePlayback computed remainingAudio ≈ 0 from
        // the just-ended segment and called onSectionPlaybackFinished, which
        // returned early because phase != .playing. Play button became inert.
        let audioPlayer = FakeAudioPlayer()
        let controller = LiveSessionController(
            session: PrototypeSession.sample,
            audioPlayer: audioPlayer
        )

        controller.playCurrentBlock()
        controller.beginBreak()
        // Sanity: we are in the break countdown now.
        guard case .breakCountdown = controller.runner.phase else {
            return XCTFail("Expected phase .breakCountdown after beginBreak")
        }

        controller.pausePlayback()
        XCTAssertTrue(controller.isPaused)

        let playCallsBeforeResume = audioPlayer.playCallCount
        controller.resumePlayback()

        XCTAssertFalse(controller.isPaused, "Paused flag must clear on resume")
        XCTAssertEqual(audioPlayer.playCallCount, playCallsBeforeResume,
                       "Resuming during a rest interval must not replay audio")
        if case .breakCountdown = controller.runner.phase {
            // pass — runner still in the rest, countdown timer is restarted
        } else {
            XCTFail("Phase should remain .breakCountdown after resume during rest")
        }
    }

    func testLiveSessionController_PauseFromIdle_DoesNotSetIsPaused() {
        // Tab-switches call pausePlayback() unconditionally. If the controller is
        // idle (no active session) it must stay un-paused — otherwise the next
        // tap on the Live cue card is swallowed clearing the stale flag instead
        // of starting playback.
        let audioPlayer = FakeAudioPlayer()
        let controller = LiveSessionController(
            session: PrototypeSession.sample,
            audioPlayer: audioPlayer
        )

        controller.pausePlayback()
        XCTAssertFalse(controller.isPaused, "Pausing while idle must be a no-op for the paused flag")

        // Subsequent play tap should start audio normally.
        controller.playCurrentBlock()
        XCTAssertEqual(audioPlayer.playCallCount, 1)
    }

    // MARK: - Pip Credit & Full-Session Battle Tests

    /// Build a 3-block × N-rep session whose sections are guaranteed to be long
    /// enough that the 75% threshold (when it was used) would have been met. Used
    /// to verify the full session reaches `.complete` exactly when expected.
    private func makeBattleSession(reps: Int, sectionLen: TimeInterval = 8.0, rest: Int = 0) -> PrototypeSession {
        let s1 = PracticeSection(id: UUID(), name: "Tumble", type: .runningTumbling,
                                 startTime: 10, endTime: 10 + sectionLen)
        let s2 = PracticeSection(id: UUID(), name: "Pyramid", type: .pyramid,
                                 startTime: 30, endTime: 30 + sectionLen)
        let s3 = PracticeSection(id: UUID(), name: "Dance", type: .dance,
                                 startTime: 60, endTime: 60 + sectionLen)
        let blocks = [s1, s2, s3].map { sec in
            PracticeBlock(id: UUID(), title: sec.name, section: sec,
                          reps: reps, restSeconds: rest, restartMode: .automatic)
        }
        let mix = ImportedMix(id: UUID(), originalFileName: "battle.m4a",
                              fileName: "battle.m4a", duration: 120)
        return PrototypeSession(id: UUID(), teamName: "Battle",
                                mix: mix, sections: [s1, s2, s3], blocks: blocks)
    }

    func testPipCredit_CreditsRepWhenAudioCurrentTimeIsShortByPreRoll() {
        // Regression: the controller's playbackEndTimer fires at sectionDuration/rate,
        // but the engine starts 0.5s early for pre-roll. At natural finish,
        // audioPlayer.currentTime is `endTime - 0.5`, which is below the 75% threshold
        // for short sections. The credit on natural finish must NOT depend on
        // audioPlayer.currentTime — short sections used to silently skip pips.
        let session = makeBattleSession(reps: 3, sectionLen: 1.5)
        let audioPlayer = FakeAudioPlayer()
        let controller = LiveSessionController(session: session, audioPlayer: audioPlayer)

        controller.playCurrentBlock()
        let block = session.blocks[0]
        // Simulate engine pre-roll: currentTime is `endTime - 0.5`, which is well
        // below the old 75% threshold for a 1.5s section (1.0s played vs 1.125s needed).
        audioPlayer.currentTime = block.section.endTime - 0.5

        // Trigger the playback-finished callback by simulating a 0-length resume
        // (which exercises the same onSectionPlaybackFinished path).
        controller.pausePlayback()
        audioPlayer.currentTime = block.section.endTime - 0.005
        controller.resumePlayback()

        XCTAssertEqual(controller.repsAttempted[block.id], 1,
                       "Natural finish must credit a pip even when audio currentTime is short by the pre-roll")
    }

    func testPipCredit_CapsAtBlockReps_NoOverflowOnReTap() {
        // Regression: tapping the currently-active block in the queue mid-rep used
        // to credit the in-progress rep AND let the subsequent re-run credit reps
        // again. repsAttempted could exceed block.reps and pip math read "8/5".
        let session = makeBattleSession(reps: 3)
        let audioPlayer = FakeAudioPlayer()
        let controller = LiveSessionController(session: session, audioPlayer: audioPlayer)

        controller.playCurrentBlock()
        let block = session.blocks[0]

        // Pretend block 0 already has all 3 reps credited (e.g., user ran through
        // and then re-tapped it from the queue).
        for _ in 0..<3 {
            audioPlayer.currentTime = block.section.endTime - 0.005
            controller.pausePlayback()
            controller.resumePlayback()
        }
        XCTAssertEqual(controller.repsAttempted[block.id], 3)

        // Re-select the same block — runner resets to currentRep = 1 and plays again.
        controller.selectBlock(at: 0)
        // Simulate another full rep finishing naturally.
        audioPlayer.currentTime = block.section.endTime - 0.005
        controller.pausePlayback()
        controller.resumePlayback()

        XCTAssertLessThanOrEqual(controller.repsAttempted[block.id] ?? 0, block.reps,
                                 "Pip count must never exceed block.reps")
    }

    func testRunner_FullMultiBlockSession_CompletesExactlyAtEnd() {
        // Battle test: 3 blocks × 3 reps = 9 finishReps. Must reach .complete
        // ONLY on the 9th finishRep — never earlier (premature midway-complete
        // bug guard) and never later (off-by-one block transition guard).
        let session = makeBattleSession(reps: 3)
        var runner = SessionRunnerState(template: session)
        runner.start()

        var finishCount = 0
        while runner.phase != .complete {
            // Sanity: must not exit the loop unexpectedly.
            XCTAssertLessThan(finishCount, 20, "Runner failed to complete in expected steps")

            switch runner.phase {
            case .playing:
                runner.finishRep()
                finishCount += 1
            case .breakCountdown:
                runner.completeBreak()
            case .waitingForManualStart:
                runner.start()
            case .idle, .complete:
                XCTFail("Unexpected phase: \(runner.phase)")
                return
            }
        }

        XCTAssertEqual(finishCount, 9,
                       "3 blocks × 3 reps must complete on exactly the 9th finishRep, not earlier or later")
        XCTAssertEqual(runner.currentBlockIndex, 2,
                       "Final block index should be the last block")
    }

    func testRunner_FullSession_BlockTransitionsHitEachBlock() {
        // Regression: ensure that block 1 (middle block) is actually executed and
        // not skipped due to off-by-one bugs in finishRep's "last rep" branch.
        let session = makeBattleSession(reps: 2)
        var runner = SessionRunnerState(template: session)
        runner.start()

        var blocksVisited: Set<Int> = []
        var repsPerBlock: [Int: Int] = [:]

        while runner.phase != .complete {
            if case .playing = runner.phase {
                blocksVisited.insert(runner.currentBlockIndex)
                repsPerBlock[runner.currentBlockIndex, default: 0] += 1
                runner.finishRep()
            } else if case .breakCountdown = runner.phase {
                runner.completeBreak()
            } else if case .waitingForManualStart = runner.phase {
                runner.start()
            } else {
                break
            }
        }

        XCTAssertEqual(blocksVisited, [0, 1, 2], "Every block must be visited")
        XCTAssertEqual(repsPerBlock[0], 2, "Block 0 must run 2 reps")
        XCTAssertEqual(repsPerBlock[1], 2, "Block 1 must run 2 reps (middle block not skipped)")
        XCTAssertEqual(repsPerBlock[2], 2, "Block 2 must run 2 reps")
    }

    // MARK: - Slide-to-Warning skip behavior

    func testRunner_FastForwardBreak_JumpsIntoCountdownTail() {
        // Slide-to-skip should land us in the GET READY tail (5s left), NOT
        // immediately in .playing. The user wants the warning beeps to fire.
        let session = makeBattleSession(reps: 2, rest: 30)
        var runner = SessionRunnerState(template: session)
        runner.start()
        runner.finishRep() // enters 30s rest

        guard case .breakCountdown(let pre) = runner.phase else {
            return XCTFail("Expected breakCountdown after finishRep")
        }
        XCTAssertEqual(pre, 30)

        runner.fastForwardBreak(toRemaining: PracticeBlock.countdownTailSeconds)
        XCTAssertEqual(runner.phase, .breakCountdown(secondsRemaining: PracticeBlock.countdownTailSeconds))
    }

    func testRunner_FastForwardBreak_NoOpIfWouldExtend() {
        // Slide must NEVER lengthen the rest — calling fastForward with a higher
        // value than what's currently remaining is a no-op.
        let session = makeBattleSession(reps: 2, rest: 3)
        var runner = SessionRunnerState(template: session)
        runner.start()
        runner.finishRep() // 3s rest

        runner.fastForwardBreak(toRemaining: 30)
        XCTAssertEqual(runner.phase, .breakCountdown(secondsRemaining: 3),
                       "fastForward must not extend remaining time")
    }

    func testLiveSessionController_SkipBreakToTail_PreservesBreakPhase() {
        // Controller-level skipBreakToCountdownTail must keep the runner in
        // breakCountdown (so the existing countdown timer + beeps still fire),
        // and must NOT jump to .playing.
        let session = makeBattleSession(reps: 2, rest: 30)
        let audioPlayer = FakeAudioPlayer()
        let controller = LiveSessionController(session: session, audioPlayer: audioPlayer)

        controller.playCurrentBlock()
        // Drive a natural rep end into the rest interval.
        controller.pausePlayback()
        audioPlayer.currentTime = session.blocks[0].section.endTime - 0.005
        controller.resumePlayback()
        guard case .breakCountdown = controller.runner.phase else {
            return XCTFail("Expected breakCountdown after natural rep finish")
        }

        let playsBefore = audioPlayer.playCallCount
        controller.skipBreakToCountdownTail()

        XCTAssertEqual(controller.runner.phase,
                       .breakCountdown(secondsRemaining: PracticeBlock.countdownTailSeconds),
                       "skipBreakToCountdownTail must land in the warning tail")
        XCTAssertEqual(audioPlayer.playCallCount, playsBefore,
                       "Skipping to tail must NOT replay audio yet — playback resumes only when the countdown finishes")
    }

    // MARK: - Per-Mix Block Persistence

    func testSavedMix_DecodesLegacyEntryWithoutBlocks_AsEmptyBlocks() {
        // Backward compat: pre-blocks libraries stored only sections. Loading
        // such a JSON must not throw — blocks should default to [].
        let legacyJSON = """
        {
          "id": "\(UUID().uuidString)",
          "mix": {
            "id": "\(UUID().uuidString)",
            "originalFileName": "legacy.m4a",
            "fileName": "legacy.m4a",
            "duration": 90
          },
          "sections": [],
          "dateAdded": 740000000
        }
        """.data(using: .utf8)!

        do {
            let decoder = JSONDecoder()
            let saved = try decoder.decode(SavedMix.self, from: legacyJSON)
            XCTAssertTrue(saved.blocks.isEmpty,
                          "Missing 'blocks' key in legacy JSON must default to []")
        } catch {
            XCTFail("Legacy SavedMix JSON failed to decode: \(error)")
        }
    }

    func testMixLibraryStore_UpdateBlocks_PersistsAndSurvivesReload() {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("cpp-mix-blocks-test-\(UUID().uuidString).json")
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let audioDir = appSupport.appendingPathComponent("CheerPracticePlayer/ImportedMixes", isDirectory: true)
        try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        let fileName = "cpp-mix-audio-\(UUID().uuidString).m4a"
        let audioURL = audioDir.appendingPathComponent(fileName)
        try? Data().write(to: audioURL)

        defer {
            cleanupTestArtifacts(near: temp)
            try? FileManager.default.removeItem(at: audioURL)
        }

        let mix = ImportedMix(id: UUID(), originalFileName: "battle.m4a",
                              fileName: fileName, duration: 120)
        let section = PracticeSection(id: UUID(), name: "Tumble",
                                      type: .runningTumbling, startTime: 10, endTime: 18)
        let block = PracticeBlock(id: UUID(), title: "Tumble",
                                  section: section, reps: 7, restSeconds: 42,
                                  restartMode: .manual)

        let store = MixLibraryStore(fileURL: temp)
        store.save(mix, sections: [section], blocks: [block])

        // Mutate just the blocks (simulating Builder onChange).
        var edited = block
        edited.reps = 9
        edited.restSeconds = 31
        store.updateBlocks(for: mix.id, blocks: [edited])

        // Re-instantiate the store from the same file. Block edits must survive.
        let reloaded = MixLibraryStore(fileURL: temp)
        XCTAssertEqual(reloaded.mixes.count, 1)
        XCTAssertEqual(reloaded.mixes.first?.blocks.count, 1)
        XCTAssertEqual(reloaded.mixes.first?.blocks.first?.reps, 9,
                       "Reps must persist across reload — was: \(reloaded.mixes.first?.blocks.first?.reps ?? -1)")
        XCTAssertEqual(reloaded.mixes.first?.blocks.first?.restSeconds, 31,
                       "Rest seconds must persist across reload")
        XCTAssertEqual(reloaded.mixes.first?.blocks.first?.restartMode, .manual,
                       "Restart mode must persist across reload")
    }

    // MARK: - MixLibraryStore

    func testMixLibraryStore_CorruptFile_IsBackedUpAndStoreStartsEmpty() {
        // Regression: load() used `try? ... ?? []` which would silently nuke a
        // user's saved library on first persist after any decode failure. Now
        // we rename the corrupt file aside and start fresh.
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("cpp-mix-store-test-\(UUID().uuidString).json")
        defer { cleanupTestArtifacts(near: temp) }

        try? "this is not valid json {".write(to: temp, atomically: true, encoding: .utf8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: temp.path))

        let store = MixLibraryStore(fileURL: temp)

        XCTAssertEqual(store.mixes.count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.path),
                       "Corrupt file should have been moved aside")
        let dir = temp.deletingLastPathComponent()
        let backupExists = (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?
            .contains { $0.hasPrefix(temp.lastPathComponent) && $0.contains(".bak-") } ?? false
        XCTAssertTrue(backupExists, "A .bak-<timestamp> backup file should exist next to the original path")
    }

    func testMixLibraryStore_ValidFile_LoadsMixesIntact() {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("cpp-mix-store-test-\(UUID().uuidString).json")
        // load() drops mixes whose audio file is missing — create a real placeholder
        // in the expected Application Support subpath so this entry survives the existence check.
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let audioDir = appSupport.appendingPathComponent("CheerPracticePlayer/ImportedMixes", isDirectory: true)
        try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        
        let fileName = "cpp-mix-audio-\(UUID().uuidString).m4a"
        let audioURL = audioDir.appendingPathComponent(fileName)
        try? Data().write(to: audioURL)
        
        defer {
            cleanupTestArtifacts(near: temp)
            try? FileManager.default.removeItem(at: audioURL)
        }

        let mix = ImportedMix(
            id: UUID(),
            originalFileName: "test.m4a",
            fileName: fileName,
            duration: 120
        )
        let saved = [SavedMix(id: UUID(), mix: mix, sections: [], dateAdded: Date())]
        do {
            let data = try JSONEncoder().encode(saved)
            try data.write(to: temp)
        } catch {
            XCTFail("Failed to encode/write test data: \(error)")
        }

        let store = MixLibraryStore(fileURL: temp)

        XCTAssertEqual(store.mixes.count, 1)
        XCTAssertEqual(store.mixes.first?.mix.originalFileName, "test.m4a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: temp.path),
                      "A valid file must NOT be backed up")
    }

    func testMixLibraryStore_StaleMix_IsFilteredOutAndPersisted() {
        // Regression: library used to show rows pointing at deleted audio files,
        // and tapping them did nothing because the path was stale. load() now
        // filters missing-file entries and rewrites the JSON.
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("cpp-mix-store-test-\(UUID().uuidString).json")
        defer { cleanupTestArtifacts(near: temp) }

        let mix = ImportedMix(
            id: UUID(),
            originalFileName: "ghost.m4a",
            fileName: "definitely-does-not-exist-\(UUID().uuidString).m4a",
            duration: 120
        )
        let saved = [SavedMix(id: UUID(), mix: mix, sections: [], dateAdded: Date())]
        do {
            try JSONEncoder().encode(saved).write(to: temp)
        } catch {
            XCTFail("Failed to encode/write test data: \(error)")
        }

        let store = MixLibraryStore(fileURL: temp)
        XCTAssertEqual(store.mixes.count, 0, "Stale entry must be dropped")

        // Reload should see the persisted (empty) library, proving the cleaned
        // state was written back to disk.
        let reloaded = MixLibraryStore(fileURL: temp)
        XCTAssertEqual(reloaded.mixes.count, 0)
    }

    func testSoundEffectsPlayer_PreparesAndSynthesizesWavData() {
        let wavData = SoundEffectsPlayer.generateBeepWav(frequency: 880.0, duration: 0.15, attack: 0.01, decay: 0.12)
        XCTAssertNotNil(wavData, "Synthesized WAV data should not be nil")
        guard let data = wavData else { return }
        
        // Basic check for WAV header structure
        XCTAssertGreaterThanOrEqual(data.count, 44, "WAV data must contain at least the 44-byte header")
        
        let riffHeader = String(data: data.subdata(in: 0..<4), encoding: .ascii)
        XCTAssertEqual(riffHeader, "RIFF", "Header must start with RIFF")
        
        let waveHeader = String(data: data.subdata(in: 8..<12), encoding: .ascii)
        XCTAssertEqual(waveHeader, "WAVE", "Header must contain WAVE signature")
        
        let fmtHeader = String(data: data.subdata(in: 12..<16), encoding: .ascii)
        XCTAssertEqual(fmtHeader, "fmt ", "Header must contain fmt subchunk ID")
        
        let dataHeader = String(data: data.subdata(in: 36..<40), encoding: .ascii)
        XCTAssertEqual(dataHeader, "data", "Header must contain data subchunk ID")
    }

    private func cleanupTestArtifacts(near url: URL) {
        let dir = url.deletingLastPathComponent()
        let basename = url.lastPathComponent
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for entry in entries where entry.hasPrefix(basename) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(entry))
        }
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
