import AppKit
import Carbon
import InputMethodKit
import OSLog

// Preserve the registered input-source identity so existing installations keep working.
let identifier = "com.lingolive.inputmethod.Mac"
let mode = identifier + ".Hans"
let connection = identifier + "_Connection"
let bundle = Bundle.main

func inputSource(_ id: String) -> TISInputSource? {
    let properties = [kTISPropertyInputSourceID as String: id] as CFDictionary
    return (TISCreateInputSourceList(properties, true)?.takeRetainedValue() as? [TISInputSource])?.first
}

func prepareRime() throws {
    guard let support = bundle.resourceURL?.appendingPathComponent("Rime") else { throw CocoaError(.fileNoSuchFile) }
    let data = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("LingoLive/Rime", isDirectory: true)
    try Pinyin.start(support: support, user: data)
}

if let command = CommandLine.arguments.dropFirst().first {
    switch command {
    case "--register-system":
        guard geteuid() == 0, bundle.bundleURL.path == "/Library/Input Methods/LingoLive.app" else {
            fputs("此命令供系统安装器注册 /Library/Input Methods 中的语流。\n", stderr)
            exit(1)
        }
        let status = TISRegisterInputSource(bundle.bundleURL as CFURL)
        guard status == noErr else {
            fputs("系统注册失败 (\(status))\n", stderr)
            exit(1)
        }
        print("已请求 macOS 注册系统输入源。")
        exit(0)
    case "--register":
        let status = TISRegisterInputSource(bundle.bundleURL as CFURL)
        if status != noErr {
            fputs("注册输入法失败 (\(status))\n", stderr)
            exit(1)
        }
        // Registration can take a moment before TIS sees the new bundle.
        for _ in 0..<12 {
            if inputSource(mode) != nil {
                print("已注册。首次使用请在系统设置 → 键盘 → 文字输入 → 编辑 → ＋ → 简体中文中添加「语流」。")
                exit(0)
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        fputs("已请求注册。请在系统设置 → 键盘 → 输入源中手动添加；如未出现，注销后重试。\n", stderr)
        exit(2)
    case "--current":
        if let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
           let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
            print(Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue())
        }
        exit(0)
    case "--select", "--disable":
        let id = CommandLine.arguments.dropFirst(2).first ?? mode
        guard let source = inputSource(id) else { exit(1) }
        exit((command == "--select" ? TISSelectInputSource(source) : TISDisableInputSource(source)) == noErr ? 0 : 1)
    case "--prepare-rime":
        try prepareRime()
        exit(0)
    case "--probe-rime":
        guard let support = bundle.resourceURL?.appendingPathComponent("Rime"),
              let state = CommandLine.arguments.dropFirst(2).first else { exit(2) }
        try Pinyin.start(support: support, user: URL(fileURLWithPath: state))
        let engine = Pinyin()
        for phrase in ["nihao", "qingbazuixinbanwenjianfageiwo", "ceshi"] {
            engine.clear()
            let start = ContinuousClock.now
            for key in phrase.utf8 { guard engine.key(Int32(key)) else { exit(3) } }
            let candidates = engine.candidates
            guard !candidates.isEmpty, engine.choose(0), !engine.takeCommit().isEmpty else { exit(4) }
            print("\(phrase): \(candidates.joined(separator: " · ")) (\(start.duration(to: .now)))")
            if phrase == "nihao", candidates[0] != "你好" { exit(5) }
        }
        exit(0)
    default: break // Launch Services may supply its own arguments.
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
guard let server = IMKServer(name: connection, bundleIdentifier: identifier) else { exit(1) }
do { try prepareRime() }
catch { NSLog("YuliuType could not initialize the pinyin dictionary: %@", String(describing: error)) }
Logger(subsystem: "com.lingolive.inputmethod.Mac", category: "server").notice("Input method server started")
withExtendedLifetime(server) { application.run() }
