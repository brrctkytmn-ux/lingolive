import AppKit
import RimeBridge

final class Pinyin {
    static var ready = false

    static func start(support: URL, user: URL) throws {
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        ready = live_start(support.path, user.path)
        guard ready else { throw CocoaError(.fileReadCorruptFile) }
    }

    private let session = live_session()
    var ready: Bool { session != 0 }
    deinit { live_destroy(session) }
    func key(_ key: Int32) -> Bool { live_key(session, key) }
    func choose(_ index: Int) -> Bool { live_choose(session, Int32(index)) }
    func page(back: Bool) -> Bool { live_page(session, back) }
    func clear() { live_clear(session) }
    func finish() -> Bool { live_finish(session) }
    var preedit: String { take(live_preedit(session)) }
    var prediction: String { take(live_preview(session)) }
    var raw: String { take(live_raw(session)) }
    func takeCommit() -> String { take(live_commit(session)) }
    var candidates: [String] {
        var list: [String] = []
        withUnsafeMutablePointer(to: &list) { pointer in
            live_candidates(session, pointer) { opaque, text in
                guard let opaque, let text else { return }
                opaque.assumingMemoryBound(to: [String].self).pointee.append(String(cString: text))
            }
        }
        return list
    }

    private func take(_ pointer: UnsafeMutablePointer<CChar>?) -> String {
        guard let pointer else { return "" }
        defer { free(pointer) }
        return String(cString: pointer)
    }
}
