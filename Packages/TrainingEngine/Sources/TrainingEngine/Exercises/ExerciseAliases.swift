import Foundation

/// Maps exercise names from other apps' exports onto catalogue IDs. Matching is
/// case-insensitive and ignores punctuation and spacing, so "Hammer Curls" and
/// "hammer-curl" both resolve.
public enum ExerciseAliases {
    public static func exerciseID(for name: String) -> String? {
        let key = normalize(name)
        if let direct = table[key] { return direct }
        if let catalogued = catalogueByName[key] { return catalogued }
        return nil
    }

    public static func normalize(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static let catalogueByName: [String: String] = Dictionary(
        ExerciseLibrary.all.map { (normalize($0.name), $0.id) },
        uniquingKeysWith: { first, _ in first }
    )

    private static let table: [String: String] = Dictionary(uniqueKeysWithValues: [
        // Chest
        ("Hammerstrength Incline Chest Press", "hs-incline-press"),
        ("Hammerstrength Chest Press", "hs-chest-press"),
        ("Machine Bench Press", "machine-chest-press"),
        ("Smith Machine Bench Press", "smith-bench"),
        ("Smith Machine Incline Bench Press", "smith-incline-bench"),
        ("Pec Deck", "machine-fly"),
        ("Machine Tricep Dip", "machine-dip"),
        ("Dip", "dip"),
        // Back
        ("Hammerstrength Iso Row", "hs-iso-row"),
        ("Cable Row", "seated-cable-row"),
        ("Machine Row", "chest-supported-row"),
        ("Pull Up", "pull-up"),
        ("Chin Up", "chin-up"),
        ("Neutral Grip Pull Up", "neutral-pull-up"),
        ("Wide Grip Lat Pulldown", "lat-pulldown"),
        ("Rack Pulls", "rack-pull"),
        ("Dumbbell Back Fly", "rear-delt-fly"),
        ("Dumbbell Row", "db-row"),
        ("One Arm Dumbbell Row", "db-row"),
        ("Dumbbell Rear Delt Raise", "rear-delt-fly"),
        // Shoulders
        ("Hammerstrength Shoulder Press", "hs-shoulder-press"),
        // Arms
        ("Cable Tricep Pushdown", "cable-pushdown"),
        ("Cable One Arm Underhand Tricep Extension", "cable-pushdown"),
        ("Cable Rope Overhead Triceps Extension", "overhead-cable-ext"),
        ("Cable Bicep Curl", "cable-curl"),
        ("Single Arm Cable Bicep Curl", "cable-curl"),
        ("Behind the Back Cable Bicep Curl", "cable-curl"),
        ("Dumbbell Bicep Curl", "db-curl"),
        ("Seated Dumbbell Curl", "db-curl"),
        ("Hammer Curls", "hammer-curl"),
        ("Cross Body Hammer Curls", "hammer-curl"),
        ("Machine Bicep Curl", "machine-preacher-curl"),
        ("EZ-Bar Curl", "bb-curl"),
        ("EZ-Bar Reverse Grip Curl", "reverse-curl"),
        ("Palms-Up Barbell Wrist Curl", "wrist-curl"),
        ("Palms-Up Dumbbell Wrist Curl", "wrist-curl"),
        ("Palms-Down Barbell Wrist Curl", "reverse-wrist-curl"),
        ("Palms-Down Dumbbell Wrist Curl", "reverse-wrist-curl"),
        // Legs
        ("Machine Leg Press", "leg-press"),
        ("Dumbbell Bulgarian Split Squat", "bulgarian-split-squat"),
        ("Dumbbell Lunge", "walking-lunge"),
        ("Dumbbell Stiff Legged Deadlift", "db-rdl"),
        ("Smith Machine Stiff-Legged Deadlift", "smith-rdl"),
        ("Lying Hamstrings Curl", "lying-leg-curl"),
        ("Machine Hip Abductor", "hip-abduction"),
        ("Machine Hip Adductor", "hip-adduction"),
        ("Cable Hip Extension", "cable-kickback"),
        ("Back Extensions", "back-extension"),
        // Calves
        ("Seated Machine Calf Press", "seated-calf-raise"),
        ("Seated Dumbbell Calf Raise", "seated-calf-raise"),
        ("Calf Press", "standing-calf-raise"),
        ("Standing Machine Calf Press", "standing-calf-raise"),
        // Core
        ("Ab Crunch Machine", "machine-crunch"),
        ("Reverse Crunch", "hanging-leg-raise"),
        ("Decline Reverse Crunch", "hanging-leg-raise"),
        ("Leg Raise", "hanging-leg-raise"),
        ("Vertical Leg Raise", "hanging-leg-raise"),
    ].map { (normalize($0.0), $0.1) })

    /// Names that are deliberately not imported as strength work.
    public static let ignoredNames: Set<String> = Set(["Assisted Pull Up"].map(normalize))
}
