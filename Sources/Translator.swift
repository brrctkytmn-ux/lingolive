import Foundation
import Translation

let chinese = Locale.Language(identifier: "zh-Hans")
let english = Locale.Language(identifier: "en")

enum TranslateFailure: Error { case empty }

final class Translator {
    static let shared = Translator()
    private let session = TranslationSession(installedSource: chinese, target: english, preferredStrategy: .lowLatency)
    private var tail: Task<String, Error>?
    private var cache: [String: String] = [:]
    private var order: [String] = []
    private var warmed = false

    // All calls originate on the main actor; framework translation suspends without blocking typing.
    @MainActor func warm() {
        guard !warmed else { return }
        warmed = true
        Task {
            guard await session.isReady else { warmed = false; return }
            _ = try? await translate("你好")
        }
    }

    @MainActor func translate(_ source: String) async throws -> String {
        try Task.checkCancellation()
        if let hit = cache[source] { return hit }
        let previous = tail
        let job = Task { @MainActor in
            _ = await previous?.result
            try Task.checkCancellation()
            if let hit = cache[source] { return hit }
            let value = try await session.translate(source).targetText.trimmingCharacters(in: .whitespacesAndNewlines)
            try Task.checkCancellation()
            guard !value.isEmpty else { throw TranslateFailure.empty }
            cache[source] = value
            order.append(source)
            if order.count > 64 { cache.removeValue(forKey: order.removeFirst()) }
            return value
        }
        tail = job
        return try await withTaskCancellationHandler {
            try await job.value
        } onCancel: {
            job.cancel()
        }
    }
}
