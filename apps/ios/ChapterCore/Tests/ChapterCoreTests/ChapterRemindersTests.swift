// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import ChapterCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class ReminderFixtureProtocol: URLProtocol {
    static let lock = NSLock()
    static var handler: ((URLRequest, Data) -> (Int, Data))?
    static var requests = 0
    static func install(_ value: @escaping (URLRequest, Data) -> (Int, Data)) { lock.lock(); handler = value; requests = 0; lock.unlock() }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); let action = Self.handler; Self.requests += 1; Self.lock.unlock()
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open(); var buffer = [UInt8](repeating: 0, count: 4096)
            while true { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; body.append(contentsOf: buffer.prefix(n)) }
            stream.close()
        }
        guard let (code, payload) = action?(request, body),
              let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json", "Content-Length": "\(payload.count)"]) else {
            client?.urlProtocol(self, didFailWithError: ChapterError.corruptData); return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class ChapterRemindersTests: XCTestCase {
    let token = String(repeating: "A", count: 43)
    private func relay() throws -> Relay {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ReminderFixtureProtocol.self]
        return Relay(address: try ServerAddress("https://fixture.invalid/prefix"), configuration: config)
    }

    /// Vectors written by server/internal/api/reminders_native_vectors_test.go with the handler's own rules.
    func testIDsAndFireTimesMatchTheGoServerExactly() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "reminders", withExtension: "json"))
        let f = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        XCTAssertGreaterThan(f["parse"].array.count, 40)
        for c in f["ids"].array {
            let id = try XCTUnwrap(c["id"].string), ok = c["ok"] == .bool(true)
            XCTAssertEqual(ChapterReminders.serverAcceptsID(id), ok, id)
            XCTAssertEqual(ChapterReminders.validID(id), ok && id != "." && id != "..", id)
        }
        for c in f["parse"].array {
            let input = try XCTUnwrap(c["in"].string), parsed = ChapterReminders.parse(input)
            if c["ok"] == .bool(true) {
                XCTAssertEqual(parsed?.seconds, Int64(c["unix"].number ?? 0), input)
                XCTAssertEqual(parsed?.nanos, Int(c["nanos"].number ?? 0), input)
            } else { XCTAssertNil(parsed.map { "\($0)" }, input) }
        }
        for c in f["formats"].array {
            let unix = try XCTUnwrap(c["unix"].number), nanos = c["nanos"].number ?? 0
            // A Date (Double seconds) can't hold every nanosecond: 1794232800 + 0.999999999 rounds up to the next second.
            guard (unix + nanos / 1e9).rounded(.down) == unix else { continue }
            let out = try ChapterReminders.format(Date(timeIntervalSince1970: unix + nanos / 1e9))
            XCTAssertEqual(out, c["out"].string, "\(unix)")
            XCTAssertEqual(ChapterReminders.parse(out)?.seconds, Int64((unix + nanos / 1e9).rounded(.down)))
        }
        XCTAssertThrowsError(try ChapterReminders.format(Date(timeIntervalSince1970: 253402300800))) // year 10000
        XCTAssertThrowsError(try ChapterReminders.format(Date(timeIntervalSince1970: -62167219201))) // year -1
    }

    func testRelayRemindersUseTheServerWireFormat() async throws {
        ReminderFixtureProtocol.install { request, _ in
            XCTAssertEqual(request.httpMethod, "GET"); XCTAssertEqual(request.url?.path, "/prefix/v1/reminders")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + String(repeating: "A", count: 43))
            return (200, Data(#"{"reminders":[{"reminder_id":"daily","fire_at":"2026-11-10T14:00:00Z","dispatched":false},{"reminder_id":"old.1","fire_at":"2026-11-08T14:00:00Z","dispatched":true}]}"#.utf8))
        }
        let client = try relay(); defer { client.cancel() }
        let list = try await client.reminders(token: token)
        XCTAssertEqual(list, [ChapterReminders.Reminder(id: "daily", fireAt: Date(timeIntervalSince1970: 1794319200)), ChapterReminders.Reminder(id: "old.1", fireAt: Date(timeIntervalSince1970: 1794146400), dispatched: true)])

        for bad in [#"{"reminders":[{"reminder_id":"x","fire_at":"tomorrow","dispatched":false}]}"#, #"{"reminders":[{"reminder_id":"a/b","fire_at":"2026-11-10T14:00:00Z","dispatched":false}]}"#, #"{"nope":1}"#] {
            ReminderFixtureProtocol.install { _, _ in (200, Data(bad.utf8)) }
            do { _ = try await client.reminders(token: token); XCTFail(bad) } catch {}
        }

        ReminderFixtureProtocol.install { request, body in
            XCTAssertEqual(request.httpMethod, "PUT"); XCTAssertEqual(request.url?.path, "/prefix/v1/reminders")
            let sent = try? JSONDecoder().decode([String: String].self, from: body)
            XCTAssertEqual(sent, ["reminder_id": "daily", "fire_at": "2026-11-10T14:00:00Z"])
            return (200, Data(#"{"reminder_id":"daily"}"#.utf8))
        }
        try await client.putReminder(id: "daily", fireAt: Date(timeIntervalSince1970: 1794319200.75), token: token)
        ReminderFixtureProtocol.install { _, _ in (200, Data(#"{"reminder_id":"other"}"#.utf8)) }
        do { try await client.putReminder(id: "daily", fireAt: Date(), token: token); XCTFail("echo must match") } catch ChapterError.corruptData {}
        ReminderFixtureProtocol.install { _, _ in (400, Data(#"{"error":"fire_at must be RFC3339"}"#.utf8)) }
        do { try await client.putReminder(id: "daily", fireAt: Date(), token: token); XCTFail("400") } catch ChapterError.http(let code) { XCTAssertEqual(code, 400) }

        ReminderFixtureProtocol.install { request, _ in
            XCTAssertEqual(request.httpMethod, "DELETE"); XCTAssertEqual(request.url?.path, "/prefix/v1/reminders/a.b:c_d-e")
            return (204, Data())
        }
        try await client.deleteReminder(id: "a.b:c_d-e", token: token)
        ReminderFixtureProtocol.install { _, _ in (404, Data(#"{"error":"no such reminder"}"#.utf8)) }
        do { try await client.deleteReminder(id: "gone", token: token); XCTFail("404") } catch ChapterError.http(let code) { XCTAssertEqual(code, 404) }
        ReminderFixtureProtocol.install { _, _ in (200, Data()) }
        do { try await client.deleteReminder(id: "gone", token: token); XCTFail("only 204") } catch ChapterError.corruptData {}

        ReminderFixtureProtocol.install { _, _ in XCTFail("no request for refused ids"); return (204, Data()) }
        for id in ["..", ".", "a/b", "", String(repeating: "a", count: 129)] {
            do { try await client.deleteReminder(id: id, token: token); XCTFail(id) } catch ChapterError.unsupported {}
            do { try await client.putReminder(id: id, fireAt: Date(), token: token); XCTFail(id) } catch ChapterError.unsupported {}
        }
        XCTAssertEqual(ReminderFixtureProtocol.requests, 0)
    }

    func testLocalNotificationPlanAndReconcile() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func r(_ id: String, _ dt: Double, _ dispatched: Bool = false) -> ChapterReminders.Reminder { .init(id: id, fireAt: now.addingTimeInterval(dt), dispatched: dispatched) }
        let plan = ChapterReminders.plan([r("late", 300), r("past", -1), r("now", 0), r("b", 60), r("a", 60), r("claimed", 120, true), r("a", 999), r("a/b", 10)], now: now)
        XCTAssertEqual(plan.map(\.identifier), ["chapter.reminder.a", "chapter.reminder.b", "chapter.reminder.claimed", "chapter.reminder.late"])
        XCTAssertEqual(plan.first?.fireAt, now.addingTimeInterval(60))
        let many = (0..<100).map { r(String(format: "r%03d", $0), Double(100 - $0)) }
        let capped = ChapterReminders.plan(many, now: now)
        XCTAssertEqual(capped.count, 64); XCTAssertEqual(capped.first?.identifier, "chapter.reminder.r099"); XCTAssertEqual(capped.last?.identifier, "chapter.reminder.r036")
        XCTAssertEqual(ChapterReminders.plan(many, now: now, limit: 0), [])

        let pending: [ChapterReminders.Notification] = [
            .init(identifier: "chapter.reminder.a", fireAt: now.addingTimeInterval(60)),
            .init(identifier: "chapter.reminder.b", fireAt: now.addingTimeInterval(30)),
            .init(identifier: "chapter.reminder.gone", fireAt: now.addingTimeInterval(30)),
            .init(identifier: "someone.else", fireAt: now.addingTimeInterval(30)),
        ]
        let change = ChapterReminders.reconcile(pending: pending, plan: plan)
        XCTAssertEqual(change.remove, ["chapter.reminder.gone"])
        XCTAssertEqual(change.add.map(\.identifier), ["chapter.reminder.b", "chapter.reminder.claimed", "chapter.reminder.late"])
        let settled = ChapterReminders.reconcile(pending: plan, plan: plan)
        XCTAssertTrue(settled.add.isEmpty && settled.remove.isEmpty)
    }
}
