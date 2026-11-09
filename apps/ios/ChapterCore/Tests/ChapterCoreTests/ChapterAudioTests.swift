// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import ChapterCore

/// The web's video/audiomix.ts and ui/recorder.ts, checked against vectors the web code produced
/// (scripts/native-audio-vectors.ts). Float32 outputs must be bit-identical.
final class ChapterAudioTests: XCTestCase {
    private func fixture() throws -> JSValue {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "audio-recorder", withExtension: "json"))
        return try JSValue.parse(String(decoding: try Data(contentsOf: url), as: UTF8.self))
    }
    private func items(_ v: JSValue?) -> [JSValue] { if case .array(let a)? = v { return a }; return [] }
    private func n(_ v: JSValue?) throws -> Double {
        switch v {
        case .number(let x)?: return x
        case .object?: let s = try XCTUnwrap(v?.get("$num")?.string); return ["NaN": .nan, "Infinity": .infinity, "-Infinity": -.infinity, "-0": -0.0][s]!
        default: XCTFail("not a number"); return .nan
        }
    }
    private func floats(_ v: JSValue?) throws -> [Float] { try items(v).map { Float(try n($0)) } }
    private func bits(_ a: [Float]) -> [UInt32] { a.map(\.bitPattern) }

    func testAudioMixMatchesTheWebBitForBit() throws {
        let f = try fixture()
        for (k, c) in items(f.get("downmix")).enumerated() {
            XCTAssertEqual(bits(ChapterAudioMix.downmixToMono(try items(c.get("planes")).map(floats))), bits(try floats(c.get("out"))), "downmix \(k)")
        }
        for (k, c) in items(f.get("resample")).enumerated() {
            let out = ChapterAudioMix.resampleLinear(try floats(c.get("src")), from: try n(c.get("from")), to: try n(c.get("to")))
            XCTAssertEqual(bits(out), bits(try floats(c.get("out"))), "resample \(k)")
        }
        for c in items(f.get("silence")) { XCTAssertEqual(Double(ChapterAudioMix.silence(Int(try n(c.get("frames")))).count), try n(c.get("out"))) }
        for (k, c) in items(f.get("fit")).enumerated() {
            XCTAssertEqual(bits(ChapterAudioMix.fitLength(try floats(c.get("data")), Int(try n(c.get("frames"))))), bits(try floats(c.get("out"))), "fit \(k)")
        }
        for c in items(f.get("chunks")) {
            XCTAssertEqual(ChapterAudioMix.chunkFrames(Int(try n(c.get("total"))), Int(try n(c.get("per")))).map(Double.init), try items(c.get("out")).map(n))
        }
    }

    func testRecorderSettingsAndClockMatchTheWeb() throws {
        let f = try fixture(), q = try XCTUnwrap(f.get("quality"))
        for level in ChapterRecorder.VideoQuality.allCases {
            let t = q.get("table")?.get(level.rawValue)
            XCTAssertEqual([level.width, level.height, level.bitsPerSecond].map(Double.init), [try n(t?.get("width")), try n(t?.get("height")), try n(t?.get("bitsPerSecond"))])
            XCTAssertEqual(Double(level.megabytesPerMinute), try n(q.get("mbPerMinute")?.get(level.rawValue)))
        }
        for c in items(q.get("stored")) { XCTAssertEqual(.string(ChapterRecorder.VideoQuality.stored(c.get("stored")?.string).rawValue), c.get("out")) }
        let a = try XCTUnwrap(f.get("answerLimits"))
        XCTAssertEqual(ChapterRecorder.answerLimits.map(Double.init), try items(a.get("presets")).map(n))
        for c in items(a.get("stored")) { XCTAssertEqual(ChapterRecorder.answerLimit(stored: c.get("stored")?.string), try n(c.get("out")), "stored \(c.stringify())") }
        for c in items(f.get("clock")) {
            let ms = try n(c.get("ms"))
            XCTAssertEqual(.string(ChapterRecorder.formatDuration(ms: ms)), c.get("duration"), "duration \(ms)")
            XCTAssertEqual(.string(ChapterRecorder.formatCountdown(ms: ms)), c.get("countdown"), "countdown \(ms)")
        }
    }
}
