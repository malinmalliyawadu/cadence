import Foundation
import Testing
@testable import TrainingEngine

@Suite("Swap ranking")
struct SwapRankingTests {
    let rdl = ExerciseLibrary.exercise(id: "rdl")!
    let calfRaise = ExerciseLibrary.exercise(id: "standing-calf-raise")!

    @Test("A direct substitute ranks first: same muscle, pattern and role")
    func directSubstitute() {
        let top = SwapRanking.options(replacing: rdl, focus: .posteriorChain).first!
        #expect(top.exercise.primary == rdl.primary && top.exercise.pattern == rdl.pattern && top.exercise.role == rdl.role)
        #expect(top.reason == "Same muscle and movement")
    }

    @Test("Movements the athlete has logged rank above unfamiliar ones of the same fit")
    func familiarity() {
        let options = SwapRanking.options(replacing: rdl, focus: .posteriorChain, familiarity: ["db-rdl": 12])
        #expect(options.first?.exercise.id == "db-rdl")
        #expect(options.first?.reason == "Same muscle and movement, logged 12 times")
    }

    @Test("After the direct substitutes, focus work outranks the rest of the half")
    func focusOrdering() {
        let options = SwapRanking.options(replacing: calfRaise, focus: .quads)
        #expect(options.first?.exercise.id == "seated-calf-raise")
        let afterCalves = options.dropFirst().first { $0.exercise.primary != .calves }
        #expect(afterCalves?.exercise.primary == .quads)
        #expect(afterCalves?.reason.contains("quads focus") == true)
    }

    @Test("The current movement, ones already in the session, other halves and missing equipment are left out")
    func filtering() {
        let options = SwapRanking.options(replacing: rdl, focus: .posteriorChain, excluding: ["smith-rdl"], equipment: [.machine, .dumbbell])
        let ids = Set(options.map(\.exercise.id))
        #expect(!ids.contains("rdl"))
        #expect(!ids.contains("smith-rdl"))
        #expect(options.allSatisfy { $0.exercise.half == .lower })
        #expect(options.allSatisfy { [.machine, .dumbbell].contains($0.exercise.equipment) })
        #expect(!options.isEmpty)
    }
}
