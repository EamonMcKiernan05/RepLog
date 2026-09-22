import Testing
import Foundation
@testable import RepLog

@Suite("Outbox state machine")
struct OutboxTests {
    @Test("local -> queued on finish")
    func finish() {
        var ob = Outbox()
        #expect(ob.state(of: "s1") == .local)
        ob.finish("s1")
        #expect(ob.state(of: "s1") == .queued)
        #expect(ob.dueForUpload() == ["s1"])
    }

    @Test("queued -> uploaded on success")
    func uploadOk() {
        var ob = Outbox()
        ob.finish("s1")
        ob.uploadSucceeded("s1")
        #expect(ob.state(of: "s1") == .uploaded)
        #expect(ob.dueForUpload().isEmpty)
    }

    @Test("uploaded -> dirty on edit, then re-post")
    func editAfterUpload() {
        var ob = Outbox()
        ob.finish("s1")
        ob.uploadSucceeded("s1")
        ob.editAfterUpload("s1")
        #expect(ob.state(of: "s1") == .dirty)
        #expect(ob.dueForUpload() == ["s1"])
        ob.uploadSucceeded("s1")
        #expect(ob.state(of: "s1") == .uploaded)
    }

    @Test("queued -> failed on error, retries with backoff")
    func failAndRetry() {
        var ob = Outbox()
        ob.finish("s1")
        ob.uploadFailed("s1")
        #expect(ob.state(of: "s1") == .failed)
        #expect(ob.attempts["s1"] == 1)

        // Immediately after a failure, backoff hasn't elapsed.
        let now = Date()
        let due = ob.dueForUpload(now: now, lastAttempt: ["s1": now])
        #expect(due.isEmpty)

        // After the backoff window it is due again.
        let later = now.addingTimeInterval(60)
        #expect(ob.dueForUpload(now: later, lastAttempt: ["s1": now]) == ["s1"])
    }

    @Test("backoff caps at 64x")
    func backoffCap() {
        var ob = Outbox()
        ob.finish("s1")
        for _ in 0..<20 { ob.uploadFailed("s1") }
        // 2^min(20,6) = 64s cap
        let now = Date()
        #expect(ob.dueForUpload(now: now, lastAttempt: ["s1": now]).isEmpty)
        #expect(ob.dueForUpload(now: now.addingTimeInterval(65),
                                lastAttempt: ["s1": now]) == ["s1"])
    }

    @Test("delete resolves the session")
    func delete() {
        var ob = Outbox()
        ob.finish("s1")
        ob.uploadSucceeded("s1")
        ob.delete("s1")
        #expect(ob.state(of: "s1") == .uploaded)
        #expect(ob.dueForUpload().isEmpty)
    }

    @Test("queuedCount counts queued/dirty/failed only")
    func counts() {
        var ob = Outbox()
        ob.finish("a"); ob.uploadSucceeded("a")   // uploaded
        ob.finish("b")                             // queued
        ob.finish("c"); ob.uploadSucceeded("c"); ob.editAfterUpload("c")  // dirty
        ob.finish("d"); ob.uploadFailed("d")       // failed
        #expect(ob.queuedCount == 3)
    }

    @Test("a never-seen session is local and not due")
    func unseen() {
        var ob = Outbox()
        #expect(ob.state(of: "ghost") == .local)
        #expect(ob.dueForUpload().isEmpty)
    }
}
