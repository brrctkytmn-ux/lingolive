import AppKit
import InputMethodKit
import Carbon

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
            if line == .zero, index != 0 {
                _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &line)
            }
            return line
        })
    }
}

@objc(LingoLiveController)
final class LingoLiveController: IMKInputController {
    private let composition = Composition()

    override func recognizedEvents(_ sender: Any!) -> Int { Int(NSEvent.EventTypeMask.keyDown.rawValue) }

    override func activateServer(_ sender: Any!) {
        if let client = sender as? IMKTextInput {
            client.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.ABC")
        }
        composition.start()
    }

    override func deactivateServer(_ sender: Any!) {
        composition.stop((sender as? IMKTextInput).map(CompositionClient.init))
    }

    override func commitComposition(_ sender: Any!) {
        composition.commit((sender as? IMKTextInput).map(CompositionClient.init))
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, let client = sender as? IMKTextInput else { return false }
        return composition.handle(event, client: CompositionClient(client))
    }

    override func menu() -> NSMenu! {
        let menu = NSMenu()
        let item = NSMenuItem(title: "设置与离线语言包…", action: #selector(openSetup), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
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

    private var composing: Bool { !draft.isEmpty || !(pinyin?.raw.isEmpty ?? true) }
    private var owner: ObjectIdentifier { ObjectIdentifier(self) }

    func start() {
        pinyin = Pinyin()
        Task { @MainActor in Translator.shared.warm() }
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
        let characters = event.characters ?? ""

        if composing && key == kVK_Escape {
            let wasMarked = marked
            reset()
            if wasMarked { client.mark("") }
            return true
        }
        if composing && (key == kVK_Return || key == kVK_ANSI_KeypadEnter) {
            if mods.contains(.shift) {
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
        if composing && [kVK_LeftArrow, kVK_RightArrow, kVK_Home, kVK_End, kVK_Tab, kVK_ForwardDelete].contains(key) {
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
        let visible = draft + (preedit.isEmpty ? raw : preedit)
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
        job = Task { @MainActor [weak self] in
            do {
                if !force { try await Task.sleep(for: .milliseconds(90)) }
                let result = try await Translator.shared.translate(source)
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
        Palette.shared.show(PaletteContent(candidates: pinyin?.candidates ?? [], preview: preview, committing: sending),
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
