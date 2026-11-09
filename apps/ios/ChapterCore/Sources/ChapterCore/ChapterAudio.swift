// SPDX-License-Identifier: AGPL-3.0-or-later
// Ports of the web's pure audio and recorder logic: video/audiomix.ts (the film's audio is one
// 48 kHz mono track, so every clip is downmixed and resampled onto it, with silence under each
// title card and every clip fitted to its frame count) and the pure parts of ui/recorder.ts
// (quality levels, stored-setting parsing, the M:SS clock). Float32 results match the web exactly:
// sums and interpolation happen in Double and are stored as Float32, like a Float32Array.
import Foundation

public enum ChapterAudioMix {
    /// `downmixToMono`: average the channel planes; a shorter plane contributes 0 past its end.
    public static func downmixToMono(_ planes: [[Float]]) -> [Float] {
        guard let first = planes.first else { return [] }
        if planes.count == 1 { return first }
        return (0..<first.count).map { i in
            var sum = 0.0
            for p in planes { sum += i < p.count ? Double(p[i]) : 0 }
            return Float(sum / Double(planes.count))
        }
    }
    /// `resampleLinear`: linear interpolation onto `dstRate`, at least one sample.
    public static func resampleLinear(_ src: [Float], from srcRate: Double, to dstRate: Double) -> [Float] {
        if srcRate == dstRate || src.isEmpty { return src }
        let ratio = srcRate / dstRate
        let n = Int(JS.max(1, JS.round(Double(src.count) / ratio)))
        let last = src.count - 1
        return (0..<n).map { i in
            let pos = Double(i) * ratio, i0 = pos.rounded(.down)
            if i0 >= Double(last) { return src[last] }
            let j = Int(i0), frac = pos - i0
            return Float(Double(src[j]) * (1 - frac) + Double(src[j + 1]) * frac)
        }
    }
    /// `silence`: a run of zero sample-frames.
    public static func silence(_ frames: Int) -> [Float] { [Float](repeating: 0, count: Swift.max(0, frames)) }
    /// `fitLength`: pad with silence or cut the tail to exactly `frames`.
    public static func fitLength(_ data: [Float], _ frames: Int) -> [Float] {
        if data.count == frames { return data }
        if data.count > frames { return Array(data.prefix(Swift.max(0, frames))) }
        return data + [Float](repeating: 0, count: frames - data.count)
    }
    /// `chunkFrames`: split a sample count into chunks of at most `per` (which must be positive).
    public static func chunkFrames(_ total: Int, _ per: Int) -> [Int] {
        precondition(per > 0, "chunk size must be positive")
        return stride(from: total, to: 0, by: -per).map { Swift.min(per, $0) }
    }
}

public enum ChapterRecorder {
    public enum VideoQuality: String, CaseIterable, Sendable {
        case low, medium, high
        public var width: Int { [.low: 640, .medium: 1280, .high: 1920][self]! }
        public var height: Int { [.low: 360, .medium: 720, .high: 1080][self]! }
        public var bitsPerSecond: Int { [.low: 700_000, .medium: 2_000_000, .high: 4_500_000][self]! }
        /// `megabytesPerMinute`: what the picker shows.
        public var megabytesPerMinute: Int { Int(JS.round(Double(bitsPerSecond) * 60 / 8 / 1_000_000)) }
        /// `videoQuality()` on a stored value: exact names only, else 720p.
        public static func stored(_ raw: String?) -> VideoQuality { raw.flatMap(VideoQuality.init(rawValue:)) ?? .medium }
    }
    /// The answer-length presets the picker offers.
    public static let answerLimits = [30, 60, 90, 180, 300]
    public static let defaultAnswerLimit = 90.0
    /// `answerLimitSeconds()` on a stored value: `Number(raw)` within 15…600, else 90.
    public static func answerLimit(stored raw: String?) -> Double {
        let n = raw.map(JS.number) ?? 0
        return n.isFinite && n >= 15 && n <= 600 ? n : defaultAnswerLimit
    }
    /// `fmtDuration`: "M:SS", rounded to the nearest second.
    public static func formatDuration(ms: Double) -> String { clock(JS.round(ms / 1000)) }
    /// `fmtCountdown`: "M:SS" remaining, rounded up so 0:00 means stopped.
    public static func formatCountdown(ms: Double) -> String { clock(JS.max(0, (ms / 1000).rounded(.up))) }
    static func clock(_ s: Double) -> String {
        let seconds = JSValue.numberString(s.truncatingRemainder(dividingBy: 60))
        return JSValue.numberString((s / 60).rounded(.down)) + ":" + (seconds.count < 2 ? String(repeating: "0", count: 2 - seconds.count) + seconds : seconds)
    }
}
