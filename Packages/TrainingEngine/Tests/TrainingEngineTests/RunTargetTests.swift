import Foundation
import Testing
@testable import TrainingEngine

@Suite("Run targets")
struct RunTargetTests {
    let day: TimeInterval = 86_400

    // From the athlete's export: a 10 km in 51:50 and a 30 km long run in 3:20:29.
    var runs: [RunEffort] {
        [
            RunEffort(date: .now.addingTimeInterval(-13 * day), distanceKm: 10.02, minutes: 51.83),
            RunEffort(date: .now.addingTimeInterval(-16 * day), distanceKm: 30.02, minutes: 200.48),
        ]
    }

    @Test("Fitness is the best recent run: the 10 km, not the deliberately easy long run")
    func fitness() {
        let vdot = RunPacing.fitness(from: runs)!
        #expect(abs(vdot - 38.4) < 0.5)
    }

    @Test("Easy pace lands where the athlete's long runs actually go")
    func easyPace() {
        let target = RunPacing.target(for: .easy, vdot: RunPacing.fitness(from: runs), zones: nil)
        let pace = target.pace!
        #expect(abs(pace.fastest - 360) <= 10) // about 6:00 per km
        #expect(abs(pace.slowest - 400) <= 10) // about 6:40 per km
        #expect(pace.fastest.truncatingRemainder(dividingBy: 5) == 0)
    }

    @Test("Threshold is faster than easy, long is no faster than easy, quality carries an easy band")
    func ordering() {
        let vdot = RunPacing.fitness(from: runs)
        let easy = RunPacing.target(for: .easy, vdot: vdot, zones: nil).pace!
        let long = RunPacing.target(for: .long, vdot: vdot, zones: nil).pace!
        let quality = RunPacing.target(for: .quality, vdot: vdot, zones: nil)
        #expect(quality.pace!.slowest < easy.fastest)
        #expect(long.slowest >= easy.slowest)
        #expect(quality.easyPace == easy)
        #expect(quality.zone == 4)
    }

    @Test("Old runs, short runs and impossible paces are ignored")
    func filtering() {
        let old = RunEffort(date: .now.addingTimeInterval(-90 * day), distanceKm: 10, minutes: 40)
        let short = RunEffort(date: .now, distanceKm: 1, minutes: 4)
        let glitch = RunEffort(date: .now, distanceKm: 10, minutes: 20)
        #expect(RunPacing.fitness(from: [old, short, glitch]) == nil)
    }

    @Test("Zones use heart-rate reserve when the resting rate is known")
    func zones() {
        let karvonen = HeartRateZones(maximum: 190, resting: 50)
        #expect(karvonen.range(zone: 2) == 134...148)
        let percent = HeartRateZones(maximum: 190)
        #expect(percent.range(zone: 2) == 114...133)
    }

    @Test("Max is the higher of a robust observed peak and the age prediction")
    func maximum() {
        // One 230 spike, then real peaks; the third-highest is 186.
        #expect(HeartRateZones.estimatedMaximum(dailyPeaks: [229, 188, 186, 180, 175, 170], age: 35) == 186)
        #expect(HeartRateZones.estimatedMaximum(dailyPeaks: [160, 158, 155, 150, 149], age: 35) == 184)
        #expect(HeartRateZones.estimatedMaximum(dailyPeaks: [], age: nil) == nil)
    }
}
