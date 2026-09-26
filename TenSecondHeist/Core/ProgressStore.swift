import Foundation
import SwiftUI

struct PlayerSave: Codable {
    var version = 2
    var completed: Set<String> = []
    var perfect: Set<String> = []
    var plans: [String: Plan] = [:]
    var hints: Set<String> = []
    var unlockedAssists: [String: Set<String>] = [:]
    var activeAssists: [String: AssistMode] = [:]
    var tokenBalance = 3 // Included, local-only tokens. Paid balance lives in CloudKit.
    var creditedTransactions: Set<UInt64> = [] // Legacy v2 field; never used for new purchases.
    var failures: [String: Int] = [:]
    var musicEnabled = true
    var effectsEnabled = true
    var reducedMotion = false

    init() {}
    private enum CodingKeys: String, CodingKey {
        case version, completed, perfect, plans, hints, unlockedAssists, activeAssists,
             tokenBalance, creditedTransactions, failures, musicEnabled, effectsEnabled, reducedMotion
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = 2
        completed = try values.decodeIfPresent(Set<String>.self, forKey: .completed) ?? []
        perfect = try values.decodeIfPresent(Set<String>.self, forKey: .perfect) ?? []
        plans = try values.decodeIfPresent([String: Plan].self, forKey: .plans) ?? [:]
        hints = try values.decodeIfPresent(Set<String>.self, forKey: .hints) ?? []
        unlockedAssists = try values.decodeIfPresent([String: Set<String>].self, forKey: .unlockedAssists) ?? [:]
        activeAssists = try values.decodeIfPresent([String: AssistMode].self, forKey: .activeAssists) ?? [:]
        tokenBalance = try values.decodeIfPresent(Int.self, forKey: .tokenBalance) ?? 3
        creditedTransactions = try values.decodeIfPresent(Set<UInt64>.self, forKey: .creditedTransactions) ?? []
        failures = try values.decodeIfPresent([String: Int].self, forKey: .failures) ?? [:]
        musicEnabled = try values.decodeIfPresent(Bool.self, forKey: .musicEnabled) ?? true
        effectsEnabled = try values.decodeIfPresent(Bool.self, forKey: .effectsEnabled) ?? true
        reducedMotion = try values.decodeIfPresent(Bool.self, forKey: .reducedMotion) ?? false
        let sourceVersion = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        guard sourceVersion <= 2 else {
            throw NSError(domain: "TenSecondHeist", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "This save was created by a newer app version."])
        }
    }
}

@MainActor final class ProgressStore: ObservableObject {
    @Published private(set) var save: PlayerSave
    @Published private(set) var error: String?
    let levels: [LevelDefinition]
    private let saveURL: URL

    init(levels: [LevelDefinition], saveURL: URL? = nil) {
        self.levels = levels
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.saveURL = saveURL ?? directory.appendingPathComponent("TenSecondHeist", isDirectory: true)
            .appendingPathComponent("save-v2.json")
        do {
            if FileManager.default.fileExists(atPath: self.saveURL.path) {
                save = try JSONDecoder().decode(PlayerSave.self, from: Data(contentsOf: self.saveURL))
            } else { save = PlayerSave() }
        } catch {
            save = PlayerSave()
            self.error = "Your progress could not be read: \(error.localizedDescription). The existing file is preserved."
        }
    }

    @discardableResult private func commit(_ update: (inout PlayerSave) -> Void) -> Bool {
        guard error == nil else { return false }
        var next = save
        update(&next)
        do {
            try FileManager.default.createDirectory(at: saveURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: saveURL, options: .atomic)
            save = next
            return true
        } catch {
            self.error = "Progress could not be saved: \(error.localizedDescription)"
            return false
        }
    }

    func plan(for level: LevelDefinition) -> Plan { save.plans[level.id] ?? Plan() }
    func storePlan(_ plan: Plan, for level: LevelDefinition) {
        commit { $0.plans[level.id] = plan }
    }
    func complete(_ level: LevelDefinition, plan: Plan, assisted: Bool) {
        commit {
            $0.completed.insert(level.id)
            if !assisted && plan.actionCount <= level.actionTarget { $0.perfect.insert(level.id) }
        }
    }
    func failed(_ level: LevelDefinition) {
        commit { $0.failures[level.id, default: 0] += 1 }
    }
    func setMusic(_ enabled: Bool) { commit { $0.musicEnabled = enabled } }
    func setEffects(_ enabled: Bool) { commit { $0.effectsEnabled = enabled } }
    func setReducedMotion(_ enabled: Bool) { commit { $0.reducedMotion = enabled } }
    func isUnlocked(_ mode: AssistMode, level: LevelDefinition) -> Bool {
        save.unlockedAssists[level.id]?.contains(key(mode)) ?? false
    }
    func activate(_ mode: AssistMode, level: LevelDefinition) -> Bool {
        let identifier = key(mode)
        if isUnlocked(mode, level: level) {
            return commit { $0.activeAssists[level.id] = mode }
        }
        guard save.tokenBalance > 0 else { return false }
        return commit {
            $0.tokenBalance -= 1
            $0.unlockedAssists[level.id, default: []].insert(identifier)
            if mode == .tip { $0.hints.insert(level.id) }
            $0.activeAssists[level.id] = mode
        }
    }
    func deactivate(level: LevelDefinition) { commit { $0.activeAssists[level.id] = nil } }
    @discardableResult func mergePaidUnlocks(_ identifiers: Set<String>) -> Bool {
        commit { save in
            for identifier in identifiers {
                let parts = identifier.components(separatedBy: "::")
                guard parts.count == 2, levels.contains(where: { $0.id == parts[0] }),
                      parts[1] == "tip" || parts[1].hasPrefix("loop:") else { continue }
                save.unlockedAssists[parts[0], default: []].insert(parts[1])
                if parts[1] == "tip" { save.hints.insert(parts[0]) }
            }
        }
    }
    private func key(_ mode: AssistMode) -> String {
        switch mode { case .tip: "tip"; case .loop(let camera): "loop:\(camera)" }
    }
}
