import Foundation
import Translation

@main
struct TranslationBenchmark {
    @MainActor static func main() async throws {
        let status = await LanguageAvailability(preferredStrategy: .lowLatency).status(from: chinese, to: TranslationTarget.english.language)
        guard status == .installed else {
            print("SKIP: Chinese and English translation assets are not installed.")
            return
        }
        let translator = Translator.forTarget(.english)
        _ = try await translator.translate("你好")
        let cases = [
            "请把最新版文件发给我。",
            "明天下午三点开会。",
            "我已经确认收到款项。",
            "这批商品还没发货。",
            "如果需要改期，请提前告诉我。",
            "这个订单请不要取消。",
            "库存只剩十二件。",
            "周五之前能发货吗？"
        ]
        var times: [Double] = []
        for source in cases {
            let start = ContinuousClock.now
            let target = try await translator.translate(source)
            let time = start.duration(to: .now).components
            let ms = Double(time.seconds) * 1000 + Double(time.attoseconds) / 1e15
            times.append(ms)
            print(String(format: "%.0f ms", ms), source, "→", target)
            guard target.range(of: "[a-zA-Z]", options: .regularExpression) != nil else { exit(1) }
        }
        let sorted = times.sorted()
        print(String(format: "Engine only: median %.0f ms, range %.0f–%.0f ms.", (sorted[3] + sorted[4]) / 2, sorted[0], sorted[7]))
    }
}
