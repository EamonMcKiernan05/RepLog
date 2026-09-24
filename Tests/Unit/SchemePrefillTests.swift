import Testing
import Foundation
@testable import RepLog

/// The routine-scheme pre-fill rule (owner report, 2026-09-24: a brand-new
/// session arrived with a committed "0" and "4" in the first set).
@Suite("Scheme pre-fill")
struct SchemePrefillTests {

    @Test("a zero-weight scheme row pre-fills nothing")
    func zeroWeight() {
        #expect(SchemePrefill.values(for: [0, 4]) == nil)
    }

    @Test("a real scheme row pre-fills weight and reps")
    func realRow() {
        let v = SchemePrefill.values(for: [100, 5])
        #expect(v?.weightKg == 100)
        #expect(v?.reps == 5)
    }

    @Test("zero reps pre-fills nothing")
    func zeroReps() {
        #expect(SchemePrefill.values(for: [100, 0]) == nil)
    }

    @Test("a missing row pre-fills nothing")
    func missingRow() {
        #expect(SchemePrefill.values(for: nil) == nil)
    }

    @Test("a half-written row pre-fills nothing")
    func halfRow() {
        #expect(SchemePrefill.values(for: [100]) == nil)
    }

    @Test("negative weight pre-fills nothing")
    func negative() {
        #expect(SchemePrefill.values(for: [-5, 5]) == nil)
    }

    @Test("set rows come from the counts, never fewer than the scheme rows")
    func setCounts() {
        #expect(SchemePrefill.setCount(warmupSets: 1, workingSets: 4, schemeRows: 0) == 5)
        #expect(SchemePrefill.setCount(warmupSets: 0, workingSets: 3, schemeRows: 5) == 5)
        #expect(SchemePrefill.setCount(warmupSets: 0, workingSets: 0, schemeRows: 4) == 4)
    }
}
