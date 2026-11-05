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
        let availability = LanguageAvailability(preferredStrategy: .lowLatency)
        let englishReady = await availability.status(from: chinese, to: TranslationTarget.english.language) == .installed
        let japaneseReady = await availability.status(from: chinese, to: TranslationTarget.japanese.language) == .installed
        func waitForPreview() async throws -> String {
            let start = ContinuousClock.now
            while ContinuousClock.now < start.advanced(by: .seconds(4)) {
                if case .translated(let value) = composition.preview { return value }
                try await Task.sleep(for: .milliseconds(5))
            }
            fatalError("No live preview")
        }

        type("nihao")
        precondition(marked == "你好" && inserted.isEmpty)
        key(" ", code: kVK_Space)
        precondition(marked == "你好")
        key("\t", code: kVK_Tab)
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

        composition.start()
        let sentence = "qingbazuixinbanwenjianfageiwo"
        if englishReady {
            type(sentence)
            key(".", code: kVK_ANSI_Period)
            precondition(marked == "请把最新版文件发给我。")
            let start = ContinuousClock.now
            let preview = try await waitForPreview()
            let elapsed = start.duration(to: .now)
            key("\r", code: kVK_Return)
            precondition(inserted.last == preview && marked.isEmpty && preview.lowercased().contains("latest"))
            print("PASS: full sentence preview in \(elapsed), exact English commit: \(preview)")

            let count = inserted.count
            type("nihao")
            key("\r", code: kVK_Return)
            key("\u{1B}", code: kVK_Escape)
            try await Task.sleep(for: .milliseconds(350))
            precondition(inserted.count == count && composition.preview == .idle && marked.isEmpty)
            print("PASS: Escape cancels a pending English commit without late insertion.")
        } else {
            print("SKIP: English commit requires translation assets.")
        }

        if japaneseReady {
            type(sentence)
            key(".", code: kVK_ANSI_Period)
            let count = inserted.count
            key("\r", code: kVK_Return) // Queue an English commit before the debounce finishes.
            composition.selectTarget(.japanese, client: client)
            precondition(marked == "请把最新版文件发给我。" && inserted.count == count)
            let preview = try await waitForPreview()
            precondition(preview.range(of: #"[ぁ-ゖァ-ヺ]"#, options: .regularExpression) != nil)
            precondition(inserted.count == count) // The old Return must not commit either language.
            key("\r", code: kVK_Return)
            precondition(inserted.last == preview && marked.isEmpty)
            print("PASS: target switch preserves Chinese, cancels old commit, and commits Japanese: \(preview)")

            type("nihao")
            key("\t", code: kVK_Tab)
            precondition(inserted.last == "你好")
            print("PASS: Tab still commits Chinese with Japanese selected.")
        } else {
            print("SKIP: Japanese commit requires translation assets.")
        }
    }
}
