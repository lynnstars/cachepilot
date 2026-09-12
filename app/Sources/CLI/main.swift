import Foundation

// CLI 入口（与 App 共用 Sources/CachePilot 里的内核；不编译 SwiftUI 文件）
exit(CLI.run(args: Array(CommandLine.arguments.dropFirst())))
