import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// SHA-256 十六进制摘要。macOS 14+ 自带 CryptoKit；环境缺 CryptoKit 时回退 /usr/bin/shasum。
public enum SHA256Hex {

    public static func of(_ data: Data) -> String {
        #if canImport(CryptoKit)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #else
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("cp-hash-\(UUID().uuidString)")
        guard (try? data.write(to: tmp)) != nil else { return "" }
        defer { try? FileManager.default.removeItem(at: tmp) }
        return shasum(tmp.path) ?? ""
        #endif
    }

    /// 流式读取（大文件不全量进内存）
    public static func stream(read: (Int) -> Data) -> String {
        #if canImport(CryptoKit)
        var hasher = SHA256()
        while true {
            let chunk = read(4 * 1_048_576)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        #else
        var all = Data()
        while true {
            let chunk = read(4 * 1_048_576)
            if chunk.isEmpty { break }
            all.append(chunk)
        }
        return of(all)
        #endif
    }

    #if !canImport(CryptoKit)
    static func shasum(_ path: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
        p.arguments = ["-a", "256", path]
        let pipe = Pipe(); p.standardOutput = pipe
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return out.split(separator: " ").first.map(String.init)
    }
    #endif
}
