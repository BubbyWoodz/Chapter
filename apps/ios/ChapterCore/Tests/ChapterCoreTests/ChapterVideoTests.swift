// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import ChapterCore

/// The web's video/timeline.ts and editor/videointerviewData.ts, checked against vectors the web
/// code produced (scripts/native-video-vectors.ts). Non-finite numbers and -0 are {"$num": "..."}.
final class ChapterVideoTests: XCTestCase {
    private func fixture() throws -> JSValue {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "video-interview", withExtension: "json"))
        return try JSValue.parse(String(decoding: try Data(contentsOf: url), as: UTF8.self))
    }
    private func n(_ v: JSValue?) throws -> Double {
        switch v {
        case .number(let x)?: return x
        case .object?: let s = try XCTUnwrap(v?.get("$num")?.string); return ["NaN": .nan, "Infinity": .infinity, "-Infinity": -.infinity, "-0": -0.0][s]!
        default: XCTFail("not a number: \(String(describing: v))"); return .nan
        }
    }
    private func e(_ x: Double) -> JSValue {
        if x.isNaN { return .object([("$num", .string("NaN"))]) }
        if x.isInfinite { return .object([("$num", .string(x < 0 ? "-Infinity" : "Infinity"))]) }
        if x == 0 && x.sign == .minus { return .object([("$num", .string("-0"))]) }
        return .number(x)
    }
    private func items(_ v: JSValue?) -> [JSValue] { if case .array(let a)? = v { return a }; return [] }
    private func clipJSON(_ c: ChapterVideoInterview.Clip?) -> JSValue {
        guard let c else { return .null }
        var o: [(String, JSValue)] = [("id", .string(c.id)), ("kind", .string(c.kind)), ("mime", .string(c.mime)), ("bytes", e(c.bytes))]
        if let d = c.durationMs { o.append(("durationMs", e(d))) }
        if let s = c.name { o.append(("name", .string(s))) }
        if let w = c.width { o.append(("width", e(w))) }
        if let h = c.height { o.append(("height", e(h))) }
        o.append(("createdAt", e(c.createdAt)))
        return .object(o)
    }
    private func sessionJSON(_ s: ChapterVideoInterview.Session) -> JSValue {
        let cards: [JSValue] = s.cards.map { c in
            var o: [(String, JSValue)] = [("q", .string(c.q)), ("clip", clipJSON(c.clip))]
            if let t = c.transcript { o.append(("transcript", .string(t))) }
            if c.dropped { o.append(("dropped", .bool(true))) }
            return .object(o)
        }
        var o: [(String, JSValue)] = [("sessionId", .string(s.sessionId)), ("typeName", .string(s.typeName)), ("cards", .array(cards)), ("film", clipJSON(s.film)),
                                      ("renderedAt", s.renderedAt.map(e) ?? .null)]
        if let l = s.lang { o.append(("lang", .string(l))) }
        return .object(o)
    }
    private let throwsMarker = JSValue.object([("throws", .bool(true))])

    func testConstantsTimelinesAndSizesMatchTheWeb() throws {
        let f = try fixture()
        XCTAssertEqual(try n(f.get("constants")?.get("cardSeconds")), ChapterFilmTimeline.cardSeconds)
        XCTAssertEqual(try n(f.get("constants")?.get("fps")), ChapterFilmTimeline.fps)
        for (k, t) in items(f.get("timelines")).enumerated() {
            let d = try items(t.get("durations")).map(n), fps = try n(t.get("fps")), card = try n(t.get("card"))
            let p = ChapterFilmTimeline.plan(d, fps: fps, cardSeconds: card)
            let got = JSValue.object([("segments", .array(p.segments.map { .object([("kind", .string($0.kind.rawValue)), ("index", .number(Double($0.index))), ("startS", e($0.startS)), ("durationS", e($0.durationS)), ("frames", e($0.frames))]) })),
                                      ("totalS", e(p.totalS)), ("totalFrames", e(p.totalFrames))])
            XCTAssertEqual(got, t.get("out"), "timeline \(k)")
            XCTAssertEqual(e(ChapterFilmTimeline.estimateSeconds(d, cardSeconds: card)), t.get("estimate"), "estimate \(k)")
        }
        for s in items(f.get("sizes")) {
            let r = ChapterFilmTimeline.canonicalSize(displayWidth: try n(s.get("w")), displayHeight: try n(s.get("h")))
            XCTAssertEqual(JSValue.object([("width", e(r.width)), ("height", e(r.height))]), s.get("out"), "size \(s.stringify())")
        }
    }

    func testSessionCoercionAndRulesMatchTheWeb() throws {
        for (k, c) in items(try fixture().get("coerce")).enumerated() {
            let attrs = try XCTUnwrap(c.get("attrs"))
            guard c.get("out") != throwsMarker else { XCTAssertThrowsError(try ChapterVideoInterview.coerce(attrs), "case \(k)"); continue }
            let s = try ChapterVideoInterview.coerce(attrs)
            XCTAssertEqual(s.map(sessionJSON) ?? .null, c.get("out"), "case \(k): \(attrs.stringify())")
            guard let s, let d = c.get("derived") else { XCTAssertEqual(c.get("derived"), .null); continue }
            XCTAssertEqual(JSValue.array(s.cards.map { .bool($0.isAnswered) }), d.get("answered"), "answered \(k)")
            XCTAssertEqual(JSValue.array(s.attachments.map { .string($0.id) }), d.get("attachments"), "attachments \(k)")
            XCTAssertEqual(JSValue.bool(s.isFilmStale), d.get("stale"), "stale \(k)")
        }
    }

    func testTranscriptAndFilmWriteBackMatchTheWebByteForByte() throws {
        let f = try fixture(), bodies = items(f.get("bodies")).map(\.string), films = items(f.get("films"))
        func check(_ out: JSValue?, _ label: String, _ run: () throws -> String?) {
            if out == throwsMarker { XCTAssertThrowsError(try run(), label); return }
            XCTAssertEqual((try? run()).flatMap { $0.map(JSValue.string) } ?? .null, out, label)
        }
        for (k, t) in items(f.get("transcripts")).enumerated() {
            let body = bodies[Int(try n(t.get("body")))], index = Int(try n(t.get("index")))
            check(t.get("out"), "transcript \(k)") {
                try ChapterVideoInterview.setTranscript(bodyJSON: body, sessionId: t.get("sessionId")!.string!, cardIndex: index, transcript: t.get("transcript")!.string!)
            }
        }
        for (k, w) in items(f.get("filmWrites")).enumerated() {
            let body = bodies[Int(try n(w.get("body")))], film = films[Int(try n(w.get("film")))], at = try n(w.get("at"))
            check(w.get("out"), "film \(k)") { try ChapterVideoInterview.setFilm(bodyJSON: body, sessionId: w.get("sessionId")!.string!, film: film, at: at) }
        }
    }
}
