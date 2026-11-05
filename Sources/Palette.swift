import AppKit
import SwiftUI

enum Preview: Equatable {
    case idle, pending, translated(String), unavailable
}

struct PaletteContent: View {
    var candidates: [String]
    var preview: Preview
    var committing: Bool
    var target: TranslationTarget

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "character.bubble").font(.system(size: 12, weight: .medium))
                Text("中 → \(target.badge)").font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(committing ? "Esc 取消" : "↩ \(target.title)  ·  Tab 中文")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.secondary)
            if !candidates.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(candidates.enumerated()), id: \.offset) { index, candidate in
                        HStack(spacing: 4) {
                            Text(String(index + 1)).font(.system(size: 10, weight: .medium).monospacedDigit())
                            Text(candidate).font(.system(size: 13, weight: index == 0 ? .semibold : .regular))
                                .lineLimit(1)
                        }
                        .foregroundStyle(index == 0 ? Color.white : Color.primary)
                        .padding(.horizontal, 6).padding(.vertical, 4)
                        .background(index == 0 ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                    }
                }
                .accessibilityLabel("拼音候选")
            }
            Divider()
            Group {
                switch preview {
                case .translated(let value):
                    Text(value).font(.system(size: 15, weight: .medium)).foregroundStyle(.primary)
                case .pending:
                    Text(committing ? "正在准备译文…" : "正在翻译…").foregroundStyle(.secondary)
                case .unavailable:
                    Text("暂不可译 · 请检查离线语言包").foregroundStyle(.secondary)
                case .idle:
                    Text("输入拼音，空格或数字选词").foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 13))
            .lineLimit(5)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(width: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.12)))
    }
}

final class Palette {
    static let shared = Palette()
    private var owner: ObjectIdentifier?
    private lazy var panel: NSPanel = {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        return panel
    }()
    private var hosting: NSHostingView<PaletteContent>?

    func show(_ content: PaletteContent, owner: ObjectIdentifier, caret: NSRect) {
        let screens = NSScreen.screens
        var anchor = caret
        var screen = screens.first {
            caret.height > 0 && $0.frame.contains(NSPoint(x: caret.midX, y: caret.midY))
        }
        if screen == nil {
            // Some editing controls deliver key events but don't expose a caret rectangle.
            let pointer = NSEvent.mouseLocation
            screen = screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
            anchor = NSRect(x: pointer.x, y: pointer.y, width: 0, height: 14)
        }
        guard let screen else { hide(owner); return }
        self.owner = owner
        let view: NSHostingView<PaletteContent>
        if let hosting { view = hosting; view.rootView = content }
        else { view = NSHostingView(rootView: content); hosting = view; panel.contentView = view }
        let size = view.fittingSize
        let bounds = screen.visibleFrame.insetBy(dx: 6, dy: 6)
        let x = max(bounds.minX, min(anchor.minX, bounds.maxX - size.width))
        let below = anchor.minY - size.height - 6
        let y = max(bounds.minY, min(below >= bounds.minY ? below : anchor.maxY + 6, bounds.maxY - size.height))
        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide(_ owner: ObjectIdentifier) {
        guard self.owner == owner else { return }
        panel.orderOut(nil)
        hosting = nil
        panel.contentView = nil
        self.owner = nil
    }
}
