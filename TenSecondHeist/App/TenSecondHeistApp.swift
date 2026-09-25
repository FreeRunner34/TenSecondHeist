import SwiftUI

@MainActor final class GameContext: ObservableObject {
    let levels: [LevelDefinition]
    let progress: ProgressStore
    let loadError: String?
    init() {
        do {
            let loaded = try LevelCatalog.load()
            levels = loaded
            loadError = nil
        } catch {
            levels = []
            loadError = "Campaign could not be opened: \(error.localizedDescription)"
        }
        progress = ProgressStore(levels: levels)
    }
}

@main struct TenSecondHeistApp: App {
    @StateObject private var game = GameContext()
    @StateObject private var purchases = PurchaseManager()
    var body: some Scene {
        WindowGroup {
            HomeScreen()
                .environmentObject(game)
                .environmentObject(game.progress)
                .environmentObject(purchases)
                .onReceive(game.progress.$save) { Soundscape.shared.configure(save: $0) }
                .preferredColorScheme(.dark)
        }
    }
}

struct HomeScreen: View {
    @EnvironmentObject private var game: GameContext
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var purchases: PurchaseManager
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Image(systemName: "sparkle.magnifyingglass")
                            .foregroundStyle(HeistStyle.gold)
                        Text("REV POINT STUDIOS").tracking(2).font(.system(size: 10, weight: .heavy, design: .monospaced))
                        Spacer()
                        Image(systemName: "clock.arrow.circlepath").foregroundStyle(HeistStyle.teal)
                    }.foregroundStyle(HeistStyle.muted)
                    VStack(alignment: .leading, spacing: -7) {
                        Text("TEN").foregroundStyle(HeistStyle.cream)
                        Text("SECOND").foregroundStyle(HeistStyle.gold)
                        Text("HEIST").foregroundStyle(HeistStyle.cream)
                    }
                    .font(.system(size: 53, weight: .black, design: .rounded))
                    .minimumScaleFactor(0.7).lineLimit(1).tracking(-3)
                    Text("One plan. Three accomplices. Ten seconds to disappear.")
                        .font(.system(size: 17, weight: .medium)).foregroundStyle(HeistStyle.muted)
                    ZStack {
                        RoundedRectangle(cornerRadius: 24).fill(HeistStyle.panel)
                        HStack(alignment: .bottom, spacing: 9) {
                            ForEach(0..<8) { index in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(index.isMultiple(of: 2) ? HeistStyle.raised : HeistStyle.raised.opacity(0.6))
                                    .frame(height: CGFloat(65 + (index * 29) % 90))
                                    .overlay(alignment: .top) {
                                        RoundedRectangle(cornerRadius: 2).fill(index == 4 ? HeistStyle.gold : HeistStyle.teal.opacity(0.45))
                                            .frame(width: 8, height: 11).padding(.top, 15)
                                    }
                            }
                        }.padding(.horizontal, 20).padding(.bottom, 24)
                        VStack {
                            HStack {
                                Text("OPERATION  /  00:10")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                Spacer()
                                Circle().fill(HeistStyle.warning).frame(width: 8, height: 8)
                            }
                            Spacer()
                            HStack {
                                Image(systemName: "point.3.connected.trianglepath.dotted")
                                Text("PLAN THE IMPOSSIBLE")
                                Spacer()
                                Image(systemName: "arrow.up.right")
                            }.font(.system(size: 11, weight: .heavy, design: .monospaced))
                        }.foregroundStyle(HeistStyle.cream).padding(20)
                    }.frame(height: 210)
                    if let error = game.loadError ?? progress.error {
                        Text(error).foregroundStyle(HeistStyle.warning).padding(16).background(HeistStyle.panel, in: RoundedRectangle(cornerRadius: 12))
                    }
                    NavigationLink(destination: CampaignScreen()) {
                        Label(progress.save.completed.isEmpty ? "START HEIST" : "CONTINUE CAMPAIGN", systemImage: "arrow.right")
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .font(.system(size: 17, weight: .black, design: .rounded))
                            .foregroundStyle(HeistStyle.ink)
                            .background(HeistStyle.gold, in: RoundedRectangle(cornerRadius: 17))
                    }.disabled(game.levels.isEmpty)
                    HStack(spacing: 12) {
                        NavigationLink(destination: StoreScreen()) { menuCard("FULL CAMPAIGN", icon: "square.stack.3d.up", detail: "40 EXTRA OPERATIONS") }
                        NavigationLink(destination: SettingsScreen()) { menuCard("SETTINGS", icon: "slider.horizontal.3", detail: "AUDIO & SUPPORT") }
                    }
                    Text("No ads. No countdown while planning. Every rewind is yours.")
                        .font(.footnote).foregroundStyle(HeistStyle.muted)
                }.padding(20).padding(.top, 10)
            }
            .background(HeistBackground())
            .toolbar(.hidden, for: .navigationBar)
        }
    }
    private func menuCard(_ title: String, icon: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Image(systemName: icon).font(.title2).foregroundStyle(HeistStyle.teal)
            Text(title).font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundStyle(HeistStyle.cream)
            Text(detail).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(HeistStyle.muted)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(HeistStyle.panel, in: RoundedRectangle(cornerRadius: 17))
    }
}

struct CampaignScreen: View {
    @EnvironmentObject private var game: GameContext
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var purchases: PurchaseManager
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                BrandHeading(overline: "The job board", title: "Operations")
                HStack {
                    Label("\(progress.save.completed.count) / \(game.levels.count) solved", systemImage: "checkmark.seal")
                    Spacer()
                    Label("\(progress.save.perfect.count) perfect", systemImage: "sparkles")
                }.font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(HeistStyle.muted)
                ForEach(game.levels.indices, id: \.self) { index in
                    let level = game.levels[index]
                    let previousSolved = index == 0 || progress.save.completed.contains(game.levels[index - 1].id)
                    let requiresPurchase = index >= 8 && !purchases.campaignUnlocked
                    VStack(alignment: .leading, spacing: 0) {
                        if index == 0 || game.levels[index - 1].site != level.site {
                            HStack {
                                Circle().fill(HeistStyle.site(level.site)).frame(width: 8, height: 8)
                                Text(level.site.uppercased())
                                    .font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(2)
                                Spacer()
                                Text("\(min(index + 1, game.levels.count))–\(min(index + 12, game.levels.count))")
                            }.foregroundStyle(HeistStyle.site(level.site)).padding(.bottom, 13)
                        }
                        if previousSolved && !requiresPurchase {
                            NavigationLink(destination: HeistScreen(level: level)) { row(level, index: index, locked: false) }
                        } else if requiresPurchase {
                            NavigationLink(destination: StoreScreen()) { row(level, index: index, locked: true) }
                        } else {
                            row(level, index: index, locked: true).opacity(0.58)
                        }
                    }
                }
            }.padding(20)
        }.background(HeistBackground())
            .navigationTitle("CAMPAIGN").navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
    private func row(_ level: LevelDefinition, index: Int, locked: Bool) -> some View {
        HStack(spacing: 14) {
            Text(String(format: "%02d", index + 1))
                .font(.system(size: 21, weight: .black, design: .monospaced)).foregroundStyle(HeistStyle.site(level.site))
                .frame(width: 35)
            VStack(alignment: .leading, spacing: 5) {
                Text(level.title).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(HeistStyle.cream)
                Text("\(level.roles.count) CREW  ·  \(level.difficulty) / 5 RISK")
                    .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(HeistStyle.muted)
            }
            Spacer()
            Image(systemName: locked ? "lock.fill" : progress.save.perfect.contains(level.id) ? "sparkles" :
                  progress.save.completed.contains(level.id) ? "checkmark.circle.fill" : "chevron.right")
                .foregroundStyle(locked ? HeistStyle.muted : HeistStyle.teal)
        }.padding(15).background(HeistStyle.panel, in: RoundedRectangle(cornerRadius: 14))
            .padding(.bottom, 8)
    }
}

struct StoreScreen: View {
    @EnvironmentObject private var purchases: PurchaseManager
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                BrandHeading(overline: "Permanent unlock", title: "Full Campaign")
                Text("Forty more handcrafted heists across the archive, penthouse, and vault. The first eight operations are free.")
                    .font(.body).foregroundStyle(HeistStyle.muted)
                VStack(alignment: .leading, spacing: 15) {
                    Label("48 operations total", systemImage: "square.stack.3d.up.fill")
                    Label("Keep replaying and rewinding for free", systemImage: "arrow.counterclockwise")
                    Label("One permanent purchase", systemImage: "checkmark.seal.fill")
                }.font(.system(size: 15, weight: .semibold)).foregroundStyle(HeistStyle.cream)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(22)
                    .background(HeistStyle.panel, in: RoundedRectangle(cornerRadius: 20))
                if purchases.campaignUnlocked {
                    Label("Full Campaign unlocked", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(HeistStyle.teal).font(.headline)
                } else {
                    HeistButton(text: purchases.campaignProduct.map { "UNLOCK · \($0.displayPrice)" } ?? "STORE UNAVAILABLE",
                                symbol: "lock.open.fill", prominent: true) {
                        Task { await purchases.buyCampaign() }
                    }.disabled(purchases.campaignProduct == nil || purchases.busy)
                }
                HeistButton(text: "RESTORE PURCHASES", symbol: "arrow.clockwise") {
                    Task { await purchases.restore() }
                }
                if let message = purchases.message { Text(message).foregroundStyle(HeistStyle.muted).font(.footnote) }
                Divider().overlay(HeistStyle.muted)
                Text("INSIDE HELP").font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .tracking(2).foregroundStyle(HeistStyle.teal)
                Text("Three introductory tokens are included. Tips and camera loops are optional. Token packs are separate from Full Campaign and are currently unavailable while cross-device recovery is being finalized.")
                    .foregroundStyle(HeistStyle.muted).font(.footnote)
            }.padding(20)
        }.background(HeistBackground()).navigationTitle("STORE").navigationBarTitleDisplayMode(.inline)
    }
}

struct SettingsScreen: View {
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var purchases: PurchaseManager
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                BrandHeading(overline: "Customize the operation", title: "Settings")
                VStack(spacing: 0) {
                    Toggle("Music", isOn: Binding(get: { progress.save.musicEnabled }, set: { progress.setMusic($0) }))
                    Divider().overlay(HeistStyle.muted.opacity(0.3))
                    Toggle("Effects", isOn: Binding(get: { progress.save.effectsEnabled }, set: { progress.setEffects($0) }))
                    Divider().overlay(HeistStyle.muted.opacity(0.3))
                    Toggle("Reduce motion", isOn: Binding(get: { progress.save.reducedMotion }, set: { progress.setReducedMotion($0) }))
                }.tint(HeistStyle.teal).padding(18).background(HeistStyle.panel, in: RoundedRectangle(cornerRadius: 18))
                Text("Security events and results always have visual labels. The game works offline after installation; purchases need a connection.")
                    .font(.footnote).foregroundStyle(HeistStyle.muted)
                NavigationLink(destination: PrivacyScreen()) {
                    Label("Privacy", systemImage: "hand.raised.fill").frame(maxWidth: .infinity, alignment: .leading)
                }
                Link(destination: URL(string: "https://github.com/FreeRunner34/TenSecondHeist/issues/new")!) {
                    Label("Contact support", systemImage: "envelope.fill").frame(maxWidth: .infinity, alignment: .leading)
                }
                HeistButton(text: "RESTORE FULL CAMPAIGN", symbol: "arrow.clockwise") {
                    Task { await purchases.restore() }
                }
                if let message = purchases.message { Text(message).font(.footnote).foregroundStyle(HeistStyle.muted) }
                Text("Ten Second Heist · Rev Point Studios")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(HeistStyle.muted)
            }.padding(20)
        }.background(HeistBackground()).foregroundStyle(HeistStyle.cream)
            .navigationTitle("SETTINGS").navigationBarTitleDisplayMode(.inline)
    }
}

struct PrivacyScreen: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                BrandHeading(overline: "Your game, your device", title: "Privacy")
                Text("Ten Second Heist stores plans, progress, settings, and introductory assistance tokens on your device. The game has no account, advertising, analytics, tracking, or in-game uploads.")
                Text("The App Store processes the optional Full Campaign purchase. Apple may process purchase information under its own privacy policy. StoreKit checks your permanent entitlement when you open the app or restore purchases. Introductory tokens are local and cannot be recovered after reinstall.")
                Text("A replay is rendered from the game simulation and stays on your device unless you choose to share it through the iOS share sheet. No other screens or notifications are captured.")
                Text("Questions? Open the support page from Settings. Please do not post private information in a public issue.")
            }.foregroundStyle(HeistStyle.cream).frame(maxWidth: .infinity, alignment: .leading).padding(20)
        }.background(HeistBackground()).navigationTitle("PRIVACY")
    }
}
