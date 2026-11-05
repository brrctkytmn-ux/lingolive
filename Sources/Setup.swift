import AppKit
import SwiftUI
import Translation

@main
struct SetupApp: App {
    var body: some Scene {
        Window("语流 · 中译英", id: "setup") {
            SetupView()
        }
        .windowResizability(.contentSize)
    }
}

struct SetupView: View {
    private var _config = State<TranslationSession.Configuration?>(initialValue: nil)
    private var config: TranslationSession.Configuration? { get { _config.wrappedValue } nonmutating set { _config.wrappedValue = newValue } }
    private var _state = State<String>(initialValue: "正在检查语言包…")
    private var state: String { get { _state.wrappedValue } nonmutating set { _state.wrappedValue = newValue } }
    private var _ready = State<Bool>(initialValue: false)
    private var ready: Bool { get { _ready.wrappedValue } nonmutating set { _ready.wrappedValue = newValue } }
    private var _busy = State<Bool>(initialValue: false)
    private var busy: Bool { get { _busy.wrappedValue } nonmutating set { _busy.wrappedValue = newValue } }
    private var _sample = State<String>(initialValue: "")
    private var sample: String { get { _sample.wrappedValue } nonmutating set { _sample.wrappedValue = newValue } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "character.bubble.fill")
                    .font(.system(size: 33, weight: .medium)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text("语流").font(.system(size: 25, weight: .semibold))
                    Text("边写中文，边看英文").foregroundStyle(.secondary)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 7) {
                Label(state, systemImage: ready ? "checkmark.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 14, weight: .medium))
                Text("下载简体中文和英语语言包后，输入和翻译都在这台 Mac 上运行。")
                    .foregroundStyle(.secondary)
                if !sample.isEmpty { Text(sample).font(.callout) }
                HStack {
                    if busy { ProgressView().controlSize(.small) }
                    Button(ready ? "测试本地翻译" : "下载语言包") {
                        busy = true
                        sample = ""
                        if config == nil {
                            config = .init(source: chinese, target: english, preferredStrategy: .lowLatency)
                        } else { config?.invalidate() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy)
                    Button("打开键盘设置") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 7) {
                Text("在输入法菜单选择「语流」，输入全拼。").fontWeight(.medium)
                Text("空格 / 1–5 选词    ↩ 英文    Tab 中文    Esc 取消").foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 460)
        .task { await refresh() }
        .translationTask(config) { session in
            guard busy, config != nil else { return }
            do {
                try await session.prepareTranslation()
                let translated = try await session.translate("请把最新版文件发给我。").targetText
                sample = translated
                await refresh()
            } catch {
                await refresh()
                state = "尚未完成 · 可重试或在「语言与地区」下载"
            }
            busy = false
        }
    }

    private func refresh() async {
        let availability = await LanguageAvailability(preferredStrategy: .lowLatency).status(from: chinese, to: english)
        ready = availability == .installed
        state = ready ? "离线翻译已就绪" : "需要中英离线语言包"
    }
}
