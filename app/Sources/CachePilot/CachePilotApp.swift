import SwiftUI

@main
struct CachePilotApp: App {
    init() {
        // 语言：默认跟随系统（zh → 中文，其他 → 英文）；用户可在界面里手动覆盖。
        if let override = UserDefaults.standard.string(forKey: "langOverride"), !override.isEmpty {
            L10n.current = L10n.resolve(preferred: [], env: override)
        }
        let cfg = SafetyConfig.fromEnvironment()
        Actions.ensureDirs(cfg)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
