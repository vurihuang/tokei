import Foundation

final class DataLoader {
    // 数据唯一来源:复用 usage.30s.py --json
    static let scriptPath = "/Users/lank/code/claude-code-research/tools/usage-bar/usage.30s.py"

    // 同步加载(离屏截图等场景用)
    static func loadSync() -> Usage? { runScript() }

    static func load(_ completion: @escaping (Usage?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let usage = runScript()
            DispatchQueue.main.async { completion(usage) }
        }
    }

    private static func runScript() -> Usage? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["python3", scriptPath, "--json"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return try? JSONDecoder().decode(Usage.self, from: data)
    }
}
