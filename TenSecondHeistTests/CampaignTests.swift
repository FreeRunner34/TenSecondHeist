import XCTest
@testable import TenSecondHeist

final class CampaignTests: XCTestCase {
    private func campaign() throws -> [LevelDefinition] {
        try LevelCatalog.load(from: Bundle(for: CampaignTests.self))
    }

    func testEveryAuthoredReferenceWinsUnaided() throws {
        let levels = try campaign()
        XCTAssertEqual(levels.count, 48)
        XCTAssertEqual(Set(levels.map(\.id)).count, 48)
        XCTAssertEqual(Set(levels.map(\.site)).count, 4)
        for level in levels {
            XCTAssertEqual(level.map.count, 9, level.id)
            XCTAssertTrue(level.map.allSatisfy { $0.count == 9 }, level.id)
            XCTAssertNil(SimulationEngine.validate(level.reference, level: level), level.id)
            let outcome = SimulationEngine.run(level.reference, level: level).outcome
            guard case .victory(let tick) = outcome else {
                XCTFail("\(level.id): \(outcome.explanation)"); continue
            }
            XCTAssertLessThanOrEqual(tick, 40, level.id)
        }
    }

    func testFreeCampaignBoundaryAndSequentialAccess() throws {
        let levels = try campaign()
        let firstEight = Set(levels.prefix(8).map(\.id))
        XCTAssertTrue(CampaignAccess.canPlay(0, levels: levels, completed: [], campaignUnlocked: false))
        XCTAssertFalse(CampaignAccess.canPlay(1, levels: levels, completed: [], campaignUnlocked: false))
        XCTAssertTrue(CampaignAccess.canPlay(7, levels: levels, completed: firstEight, campaignUnlocked: false))
        XCTAssertFalse(CampaignAccess.canPlay(8, levels: levels, completed: firstEight, campaignUnlocked: false))
        XCTAssertTrue(CampaignAccess.canPlay(8, levels: levels, completed: firstEight, campaignUnlocked: true))
        XCTAssertFalse(CampaignAccess.canPlay(9, levels: levels, completed: firstEight, campaignUnlocked: true))
        XCTAssertFalse(CampaignAccess.canPlay(48, levels: levels, completed: firstEight, campaignUnlocked: true))
    }

    func testIdenticalPlansAndScrubsHaveIdenticalState() throws {
        let level = try XCTUnwrap(campaign().first)
        let a = SimulationEngine.run(level.reference, level: level)
        let b = SimulationEngine.run(level.reference, level: level)
        XCTAssertEqual(a.outcome, b.outcome)
        XCTAssertEqual(a.events.map(\.text), b.events.map(\.text))
        for tick in 0...40 {
            XCTAssertEqual(a.frame(at: tick).actors, b.frame(at: tick).actors)
            XCTAssertEqual(a.frame(at: tick).collected, b.frame(at: tick).collected)
        }
        XCTAssertNotEqual(a.frame(at: 0).actors[.thief], a.frame(at: 8).actors[.thief])
        XCTAssertTrue(a.frame(at: 16).collected.contains(level.loot[0].id))
        XCTAssertEqual(a.frame(at: 0).collected, [])
    }

    func testCameraTimingAndTerminalShutdown() throws {
        let levels = try campaign()
        let timing = levels[2]
        var unsafe = timing.reference
        unsafe[.thief].removeFirst() // remove the planned one-second wait
        guard case .spotted(_, let sensor, _) = SimulationEngine.run(unsafe, level: timing).outcome else {
            return XCTFail("Camera must catch a premature crossing")
        }
        XCTAssertEqual(sensor, "Camera B")
        let teamwork = levels[3]
        XCTAssertFalse(SimulationEngine.run(teamwork.reference, level: teamwork).frame(at: 12).cameras[0].active)
        var noHack = teamwork.reference
        noHack[.hacker] = []
        guard case .spotted = SimulationEngine.run(noHack, level: teamwork).outcome else {
            return XCTFail("Camera must remain active when terminal is not hacked")
        }
    }

    func testWallValidityAndAssistTiming() throws {
        let level = try campaign()[3]
        var bad = level.reference
        bad[.thief] = [.move(Tile(0, 5))]
        guard case .invalid = SimulationEngine.run(bad, level: level).outcome else {
            return XCTFail("Wall move must be rejected")
        }
        var idleThief = level.reference
        idleThief[.thief] = [] // Keep simulation running past the normal shutdown end.
        let normal = SimulationEngine.run(idleThief, level: level)
        let assisted = SimulationEngine.run(idleThief, level: level, assist: .loop(camera: "Camera C"))
        XCTAssertEqual(normal.outcome, assisted.outcome)
        XCTAssertTrue(assisted.frame(at: 31).disabledCameras.contains("Camera C"))
        XCTAssertFalse(normal.frame(at: 31).disabledCameras.contains("Camera C"))
    }

    @MainActor func testSaveRoundTripAndAtomicTokenSpending() throws {
        let level = try campaign()[0]
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = folder.appendingPathComponent("save.json")
        defer { try? FileManager.default.removeItem(at: folder) }
        let progress = ProgressStore(levels: [level], saveURL: url)
        XCTAssertEqual(progress.save.tokenBalance, 3)
        XCTAssertTrue(progress.activate(.tip, level: level))
        XCTAssertEqual(progress.save.tokenBalance, 2)
        XCTAssertTrue(progress.activate(.tip, level: level))
        XCTAssertEqual(progress.save.tokenBalance, 2)
        progress.storePlan(level.reference, for: level)
        progress.complete(level, plan: level.reference, assisted: true)
        progress.deactivate(level: level)
        let reopened = ProgressStore(levels: [level], saveURL: url)
        XCTAssertEqual(reopened.save.tokenBalance, 2)
        XCTAssertTrue(reopened.save.hints.contains(level.id))
        XCTAssertTrue(reopened.save.completed.contains(level.id))
        XCTAssertEqual(reopened.plan(for: level), level.reference)
        XCTAssertEqual(reopened.save.tokenBalance, 2)
    }

    @MainActor func testPaidWalletIdempotencyAndRecovery() throws {
        let level = try campaign()[0]
        var wallet = PaidWalletState()
        wallet.credit(transactionID: 12345, count: 5)
        wallet.credit(transactionID: 12345, count: 5)
        XCTAssertEqual(wallet.balance, 5)
        XCTAssertTrue(wallet.spend(levelID: level.id, mode: .tip))
        XCTAssertTrue(wallet.spend(levelID: level.id, mode: .tip))
        XCTAssertEqual(wallet.balance, 4)
        let recovered = try JSONDecoder().decode(PaidWalletState.self, from: JSONEncoder().encode(wallet))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = folder.appendingPathComponent("save.json")
        defer { try? FileManager.default.removeItem(at: folder) }
        let progress = ProgressStore(levels: [level], saveURL: url)
        XCTAssertTrue(progress.mergePaidUnlocks(recovered.unlocks))
        let reopened = ProgressStore(levels: [level], saveURL: url)
        XCTAssertTrue(reopened.isUnlocked(.tip, level: level))
        XCTAssertTrue(reopened.activate(.tip, level: level))
        XCTAssertEqual(reopened.save.tokenBalance, 3)
        wallet.revoke(transactionID: 12345)
        wallet.credit(transactionID: 12345, count: 5)
        XCTAssertEqual(wallet.balance, 0)
    }
}
