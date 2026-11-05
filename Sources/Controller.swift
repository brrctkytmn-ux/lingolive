import AppKit
import InputMethodKit
import Carbon
import OSLog

private let replacement = NSRange(location: NSNotFound, length: NSNotFound)

struct CompositionClient {
    var mark: (String) -> Void
    var insert: (String) -> Void
    var caret: (Int) -> NSRect

    init(mark: @escaping (String) -> Void, insert: @escaping (String) -> Void, caret: @escaping (Int) -> NSRect) {
        self.mark = mark
        self.insert = insert
        self.caret = caret
    }

    init(_ client: IMKTextInput) {
        self.init(mark: { text in
            client.setMarkedText(text, selectionRange: NSRange(location: text.utf16.count, length: 0), replacementRange: replacement)
        }, insert: { text in
            client.insertText(text, replacementRange: replacement)
        }, caret: { index in
            var line = NSRect.zero
            _ = client.attributes(forCharacterIndex: index, lineHeightRectangle: &line)
            if line.height <= 0, index != 0 {
                _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &line)
            }
            if line.height <= 0 {
                let marked = client.markedRange()
                let location = marked.location != NSNotFound ? marked.location + min(index, marked.length) : client.selectedRange().location
                if location != NSNotFound {
                    line = client.firstRect(forCharacterRange: NSRange(location: location, length: 0), actualRange: nil)
                }
            }
            return line
        })
    }
}

@objc(LingoLiveController)
final class LingoLiveController: IMKInputController {
    private let composition = Composition()
    private let logger = Logger(subsystem: "com.lingolive.inputmethod.Mac", category: "session")
    private weak var activeClient: IMKTextInput?
    private var receivedKey = false

    override init!(server: IMKServer!, delegate: Any!, client: Any!) {
        activeClient = client as? IMKTextInput
        super.init(server: server, delegate: delegate, client: client)
        logger.notice("Input session created")
    }

    override func recognizedEvents(_ sender: Any!) -> Int { Int(NSEvent.EventTypeMask.keyDown.rawValue) }

    override func activateServer(_ sender: Any!) {
        activeClient = (sender as? IMKTextInput) ?? activeClient
        activeClient?.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.ABC")
        receivedKey = false
        logger.debug("Input session activated")
        composition.start(target: TranslationTarget.selected)
    }

    override func deactivateServer(_ sender: Any!) {
        composition.stop(((sender as? IMKTextInput) ?? activeClient).map(CompositionClient.init))
        activeClient = nil
    }

    override func commitComposition(_ sender: Any!) {
        composition.commit(((sender as? IMKTextInput) ?? activeClient).map(CompositionClient.init))
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        activeClient = (sender as? IMKTextInput) ?? activeClient
        guard let event, let activeClient else { return false }
        let client = CompositionClient(activeClient)
        composition.selectTarget(TranslationTarget.selected, client: client)
        let handled = composition.handle(event, client: client)
        if !receivedKey, event.type == .keyDown {
            receivedKey = true
            logger.debug("First key delivered; handled=\(handled)")
        }
        return handled
    }

    override func menu() -> NSMenu! {
        let menu = NSMenu()
        let selected = TranslationTarget.selected
        for target in TranslationTarget.allCases {
            let choice = NSMenuItem(title: "翻译成" + target.title, action: #selector(changeTarget(_:)), keyEquivalent: "")
            choice.target = self
            choice.representedObject = target.rawValue
            choice.state = target == selected ? .on : .off
            menu.addItem(choice)
        }
        menu.addItem(.separator())
        let item = NSMenuItem(title: "设置与离线语言包…", action: #selector(openSetup), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc private func changeTarget(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let target = TranslationTarget(rawValue: id) else { return }
        TranslationTarget.selected = target
        composition.selectTarget(target, client: activeClient.map(CompositionClient.init))
    }

    @objc private func openSetup() {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("LingoLive Setup.app") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

}

final class Composition {
    private var pinyin: Pinyin?
    private var draft = ""
    private(set) var preview: Preview = .idle
    private var previewSource = ""
    private var job: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var generation = 0
    private var marked = false
    private var caret = NSRect.zero
    private var sending = false
    private var target: TranslationTarget = .english

    private var composing: Bool { !draft.isEmpty || !(pinyin?.raw.isEmpty ?? true) }
    private var owner: ObjectIdentifier { ObjectIdentifier(self) }

    func start(target: TranslationTarget = .english) {
        pinyin = Pinyin()
        if self.target == target { warm(target) }
        else { selectTarget(target) }
    }

    func selectTarget(_ target: TranslationTarget, client: CompositionClient? = nil) {
        guard self.target != target else { return }
        self.target = target
        previewSource = ""
        preview = .idle
        if composing, let client {
            // Keep the Chinese draft, but discard any result or queued commit for the previous language.
            update(client)
        } else {
            generation += 1
            job?.cancel()
            timeout?.cancel()
            sending = false
            Palette.shared.hide(owner)
        }
        warm(target)
    }

    private func warm(_ target: TranslationTarget) {
        Task { @MainActor in Translator.forTarget(target).warm() }
    }

    func stop(_ client: CompositionClient?) {
        commit(client)
        pinyin = nil
    }

    func commit(_ client: CompositionClient?) {
        guard let client, composing else { reset(); return }
        submit(source: resolve(), to: client)
    }

    func handle(_ event: NSEvent, client: CompositionClient) -> Bool {
        guard event.type == .keyDown else { return false }
        let engine = pinyin ?? Pinyin()
        pinyin = engine
        guard engine.ready else { return false }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods.contains(.command) || mods.contains(.control) || mods.contains(.option) {
            if composing { commit(client) }
            return false
        }
        let key = Int(event.keyCode)
        let characters = event.characters ?? event.charactersIgnoringModifiers ?? ""

        if composing && key == kVK_Escape {
            let wasMarked = marked
            reset()
            if wasMarked { client.mark("") }
            return true
        }
        if composing && [kVK_Return, kVK_ANSI_KeypadEnter, kVK_Tab].contains(key) {
            if key == kVK_Tab || mods.contains(.shift) {
                submit(source: resolve(), to: client)
            } else if !sending {
                let oldSource = previewSource
                let oldPreview = preview
                let source = resolve()
                if oldSource == source, case .translated(let value) = oldPreview { submit(source: value, to: client) }
                else if !containsHan(source) { submit(source: source, to: client) }
                else { update(client, force: true) }
            }
            return true
        }
        if composing && key == kVK_Delete {
            if engine.raw.isEmpty { if !draft.isEmpty { draft.removeLast() } }
            else { _ = engine.key(0xff08); draft += engine.takeCommit() }
            update(client)
            return true
        }
        if composing && [kVK_LeftArrow, kVK_RightArrow, kVK_Home, kVK_End, kVK_ForwardDelete].contains(key) {
            commit(client)
            return false
        }

        let candidates = engine.candidates
        if !engine.raw.isEmpty {
            if (key == kVK_Space || (characters.count == 1 && ("1"..."5").contains(characters))) && !candidates.isEmpty {
                let index = key == kVK_Space ? 0 : (Int(characters) ?? 1) - 1
                if index < candidates.count {
                    _ = engine.choose(index)
                    draft += engine.takeCommit()
                    update(client)
                    return true
                }
            }
            if [kVK_UpArrow, kVK_DownArrow, kVK_PageUp, kVK_PageDown].contains(key) {
                _ = engine.page(back: key == kVK_UpArrow || key == kVK_PageUp)
                update(client)
                return true
            }
        }
        if let scalar = characters.unicodeScalars.first, characters.unicodeScalars.count == 1,
           (97...122).contains(scalar.value) || (scalar.value == 39 && !engine.raw.isEmpty) {
            if engine.key(Int32(scalar.value)) {
                draft += engine.takeCommit()
                update(client)
                return true
            }
        }
        if composing, !characters.isEmpty, characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
            draft = resolve() + punctuation(characters)
            update(client)
            return true
        }
        return false
    }

    private func punctuation(_ input: String) -> String {
        [",": "，", ".": "。", "!": "！", "?": "？", ":": "：", ";": "；"][input] ?? input
    }

    private func containsHan(_ string: String) -> Bool {
        string.range(of: #"\p{Han}"#, options: .regularExpression) != nil
    }

    @discardableResult
    private func resolve() -> String {
        guard let engine = pinyin else { return draft }
        let raw = engine.raw
        if !raw.isEmpty {
            if !engine.candidates.isEmpty { _ = engine.choose(0); draft += engine.takeCommit() }
            if !engine.raw.isEmpty {
                let fallback = engine.prediction.isEmpty ? engine.raw : engine.prediction
                let committed = engine.finish() ? engine.takeCommit() : ""
                draft += committed.isEmpty ? fallback : committed
            }
        }
        engine.clear()
        return draft
    }

    private func update(_ client: CompositionClient, force: Bool = false) {
        generation += 1
        let revision = generation
        job?.cancel()
        timeout?.cancel()
        sending = force
        let raw = pinyin?.raw ?? ""
        let candidates = pinyin?.candidates ?? []
        let prediction = pinyin?.prediction ?? ""
        let source = draft + (prediction.isEmpty ? (candidates.first ?? raw) : prediction)
        if source != previewSource { preview = .idle; previewSource = source }
        let preedit = pinyin?.preedit ?? ""
        // Show the same Chinese candidate in the editor that the preview translates.
        let inline = containsHan(prediction) ? prediction : (preedit.isEmpty ? raw : preedit)
        let visible = draft + inline
        if visible.isEmpty {
            if marked { client.mark("") }
            reset()
            return
        }

        client.mark(visible)
        caret = client.caret(visible.utf16.count)
        marked = true

        guard containsHan(source) else { preview = .idle; redraw(); return }
        if case .translated = preview, !force { redraw(); return }
        preview = .pending
        redraw()
        job = Task { @MainActor [weak self, target] in
            do {
                if !force { try await Task.sleep(for: .milliseconds(90)) }
                let result = try await Translator.forTarget(target).translate(source)
                guard !Task.isCancelled, let self, self.generation == revision else { return }
                self.timeout?.cancel()
                if force { self.submit(source: result, to: client) }
                else { self.sending = false; self.preview = .translated(result); self.redraw() }
            } catch {
                guard !Task.isCancelled, let self, self.generation == revision else { return }
                self.timeout?.cancel()
                self.sending = false
                self.preview = .unavailable
                self.redraw()
            }
        }
        if force {
            timeout = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled, let self, self.generation == revision else { return }
                self.job?.cancel()
                self.sending = false
                self.preview = .unavailable
                self.redraw()
            }
        }
    }

    private func redraw() {
        Palette.shared.show(PaletteContent(candidates: pinyin?.candidates ?? [], preview: preview, committing: sending, target: target),
                            owner: owner, caret: caret)
    }

    private func submit(source: String, to client: CompositionClient) {
        reset()
        if !source.isEmpty { client.insert(source) }
    }

    private func reset() {
        generation += 1
        job?.cancel()
        timeout?.cancel()
        job = nil
        timeout = nil
        pinyin?.clear()
        draft = ""
        marked = false
        sending = false
        previewSource = ""
        preview = .idle
        Palette.shared.hide(owner)
    }
}
