import Foundation
import SwiftData
import TrainingEngine

/// The single athlete's preferences. One row, created on first launch.
@Model
final class AthleteProfile {
    var createdAt: Date
    var bodyweightKg: Double
    /// When Apple Health last supplied the bodyweight. Nil means it was entered by hand.
    var bodyweightFromHealthAt: Date?
    /// When the bodyweight was last entered by hand. Only a Health reading taken after it replaces it.
    var bodyweightEnteredAt: Date?

    // Heart rate, for run zones. Nil until Health supplies it or the athlete sets it.
    var maxHeartRate: Int?
    var restingHeartRate: Int?
    /// When Apple Health last supplied either heart-rate figure.
    var heartRateFromHealthAt: Date?
    /// Set by hand in Settings, so Health no longer updates it (a lab-tested max, say).
    var maxHeartRateSetByHand = false
    var restingHeartRateSetByHand = false

    // Weekly structure
    var strengthSessionsPerWeek: Int
    var easyRuns: Int
    var includeLongRun: Bool
    var includeQualityRun: Bool
    var yogaSessions: Int
    var yogaMinutes: Double
    var allowTwoADays: Bool
    /// 0 = Monday ... 6 = Sunday, relative to the week start.
    var unavailableDays: [Int]
    var preferredLongRunDay: Int?

    // Focus rotation
    var nextUpperFocusRaw: String
    var nextLowerFocusRaw: String

    // Movements added to every upper or lower session, as exercise IDs in the order they were added
    var alwaysIncludedUpper: [String] = []
    var alwaysIncludedLower: [String] = []

    // Gym
    var equipmentRaw: [String]

    // Location for the forecast
    var latitude: Double
    var longitude: Double
    var locationName: String
    var usesDeviceLocation: Bool

    init() {
        createdAt = .now
        bodyweightKg = 75
        strengthSessionsPerWeek = 4
        easyRuns = 1
        includeLongRun = true
        includeQualityRun = false
        yogaSessions = 1
        yogaMinutes = 60
        allowTwoADays = true
        unavailableDays = []
        preferredLongRunDay = 5
        nextUpperFocusRaw = FocusArea.chest.rawValue
        nextLowerFocusRaw = FocusArea.quads.rawValue
        equipmentRaw = Equipment.allCases.map(\.rawValue)
        latitude = -41.2924
        longitude = 174.7787
        locationName = "Wellington"
        usesDeviceLocation = false
    }

    var nextUpperFocus: FocusArea {
        get { FocusArea(rawValue: nextUpperFocusRaw) ?? .chest }
        set { nextUpperFocusRaw = newValue.rawValue }
    }

    var nextLowerFocus: FocusArea {
        get { FocusArea(rawValue: nextLowerFocusRaw) ?? .quads }
        set { nextLowerFocusRaw = newValue.rawValue }
    }

    func alwaysIncluded(for half: BodyHalf) -> [String] {
        half == .upper ? alwaysIncludedUpper : alwaysIncludedLower
    }

    var equipment: Set<Equipment> {
        get { Set(equipmentRaw.compactMap(Equipment.init(rawValue:))) }
        set { equipmentRaw = newValue.map(\.rawValue).sorted() }
    }

    var heartRateZones: HeartRateZones? {
        maxHeartRate.map { HeartRateZones(maximum: $0, resting: restingHeartRate) }
    }

    func plannerPreferences(weekStart: Date) -> PlannerPreferences {
        PlannerPreferences(
            weekStart: weekStart,
            strengthSessions: strengthSessionsPerWeek,
            easyRuns: easyRuns,
            includeLongRun: includeLongRun,
            includeQualityRun: includeQualityRun,
            yogaSessions: yogaSessions,
            unavailableDays: Set(unavailableDays),
            allowTwoADays: allowTwoADays,
            preferredLongRunDay: preferredLongRunDay,
            yogaMinutes: yogaMinutes
        )
    }
}
