import AppKit
import Carbon
import Translation

@main
struct CompositionSmoke {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let args = CommandLine.arguments.dropFirst().map { URL(fileURLWithPath: $0) }
        try Pinyin.start(support: args[0], user: args[1])

        var marked = ""
        var inserted: [String] = []
        let client = CompositionClient(mark: { marked = $0 }, insert: { inserted.append($0); marked = "" }, caret: { _ in .zero })
        let composition = Composition()
        composition.start()
        func key(_ text: String, code: Int = 0, modifiers: NSEvent.ModifierFlags = []) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                                         windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text,
                                         isARepeat: false, keyCode: UInt16(code))!
            precondition(composition.handle(event, client: client), "Composition declined a test key")
        }
        func type(_ text: String) { for letter in text { key(String(letter)) } }
        let localReady = await LanguageAvailability(preferredStrategy: .lowLatency).status(from: chinese, to: english) == .installed

        type("nihao")
        precondition(!marked.isEmpty && inserted.isEmpty)
        key(" ", code: kVK_Space)
        precondition(marked == "你好")
        key("\r", code: kVK_Return, modifiers: .shift)
        precondition(inserted == ["你好"])
        type("nihao")
        key("\u{1B}", code: kVK_Escape)
        precondition(marked.isEmpty && inserted == ["你好"])
        type("ceshi")
        key(" ", code: kVK_Space)
        key("\u{7F}", code: kVK_Delete)
        precondition(marked == "测")
        composition.stop(client)
        precondition(inserted == ["你好", "测"])
        print("PASS: candidate selection, Chinese commit, Escape, deletion, and focus loss.")

        guard localReady else { print("SKIP: English commit requires translation assets."); return }
        composition.start()
        type("qingbazuixinbanwenjianfageiwo")
        key(".", code: kVK_ANSI_Period)
        precondition(marked == "请把最新版文件发给我。")
        let start = ContinuousClock.now
        while ContinuousClock.now < start.advanced(by: .seconds(4)) {
            if case .translated = composition.preview { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        guard case let .translated(preview) = composition.preview else { fatalError("No live preview") }
        let elapsed = start.duration(to: .now)
        key("\r", code: kVK_Return)
        precondition(inserted.last == preview && marked.isEmpty && preview.lowercased().contains("latest"))
        print("PASS: full sentence preview in \(elapsed), exact English commit: \(preview)")

        type("nihao")
        key("\r", code: kVK_Return)
        key("\u{1B}", code: kVK_Escape)
        try await Task.sleep(for: .milliseconds(350))
        precondition(inserted.count == 3 && composition.preview == .idle && marked.isEmpty)
        print("PASS: Escape cancels a pending English commit without late insertion.")
    }
}
