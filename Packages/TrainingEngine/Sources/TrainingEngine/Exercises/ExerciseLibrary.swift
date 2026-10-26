import Foundation

/// The built-in movement catalogue. Kept in code rather than a database so the
/// generator's tests are deterministic and the catalogue versions with the app.
public enum ExerciseLibrary {
    public static let all: [Exercise] = upper + lower

    public static func exercise(id: String) -> Exercise? {
        byID[id]
    }

    public static func exercises(for half: BodyHalf) -> [Exercise] {
        all.filter { $0.half == half }
    }

    private static let byID: [String: Exercise] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    // MARK: Upper

    public static let upper: [Exercise] = [
        // Horizontal push
        Exercise(id: "bb-bench", name: "Barbell Bench Press", pattern: .horizontalPush, primary: .chest, secondary: [.triceps, .shoulders], equipment: .barbell, role: .compound, startingWeightKg: 40),
        Exercise(id: "db-incline-press", name: "Incline Dumbbell Press", pattern: .horizontalPush, primary: .chest, secondary: [.shoulders, .triceps], equipment: .dumbbell, role: .compound, startingWeightKg: 16),
        Exercise(id: "db-flat-press", name: "Flat Dumbbell Press", pattern: .horizontalPush, primary: .chest, secondary: [.triceps], equipment: .dumbbell, role: .accessory, startingWeightKg: 18),
        Exercise(id: "cable-fly", name: "Cable Fly", pattern: .horizontalPush, primary: .chest, equipment: .cable, role: .isolation, startingWeightKg: 10),
        Exercise(id: "dip", name: "Weighted Dip", pattern: .horizontalPush, primary: .chest, secondary: [.triceps], equipment: .bodyweight, role: .accessory, startingWeightKg: 0),
        Exercise(id: "cg-bench", name: "Close-Grip Bench Press", pattern: .horizontalPush, primary: .triceps, secondary: [.chest, .shoulders], equipment: .barbell, role: .compound, startingWeightKg: 35),
        Exercise(id: "hs-incline-press", name: "Hammer Strength Incline Press", pattern: .horizontalPush, primary: .chest, secondary: [.shoulders, .triceps], equipment: .machine, role: .compound, startingWeightKg: 20),
        Exercise(id: "hs-chest-press", name: "Hammer Strength Chest Press", pattern: .horizontalPush, primary: .chest, secondary: [.triceps], equipment: .machine, role: .compound, startingWeightKg: 20),
        Exercise(id: "machine-chest-press", name: "Machine Chest Press", pattern: .horizontalPush, primary: .chest, secondary: [.triceps], equipment: .machine, role: .compound, startingWeightKg: 40),
        Exercise(id: "smith-bench", name: "Smith Machine Bench Press", pattern: .horizontalPush, primary: .chest, secondary: [.triceps, .shoulders], equipment: .smith, role: .compound, startingWeightKg: 30),
        Exercise(id: "smith-incline-bench", name: "Smith Machine Incline Press", pattern: .horizontalPush, primary: .chest, secondary: [.shoulders, .triceps], equipment: .smith, role: .compound, startingWeightKg: 25),
        Exercise(id: "machine-fly", name: "Machine Fly", pattern: .horizontalPush, primary: .chest, equipment: .machine, role: .isolation, startingWeightKg: 35),
        Exercise(id: "machine-dip", name: "Machine Dip", pattern: .horizontalPush, primary: .triceps, secondary: [.chest], equipment: .machine, role: .accessory, startingWeightKg: 40),

        // Horizontal pull
        Exercise(id: "bb-row", name: "Barbell Row", pattern: .horizontalPull, primary: .back, secondary: [.biceps], equipment: .barbell, role: .compound, startingWeightKg: 40),
        Exercise(id: "db-row", name: "Single-Arm Dumbbell Row", pattern: .horizontalPull, primary: .back, secondary: [.biceps], equipment: .dumbbell, role: .accessory, unilateral: true, startingWeightKg: 18),
        Exercise(id: "chest-supported-row", name: "Chest-Supported Row", pattern: .horizontalPull, primary: .back, secondary: [.biceps], equipment: .machine, role: .accessory, startingWeightKg: 30),
        Exercise(id: "seated-cable-row", name: "Seated Cable Row", pattern: .horizontalPull, primary: .back, secondary: [.biceps], equipment: .cable, role: .accessory, startingWeightKg: 35),
        Exercise(id: "face-pull", name: "Face Pull", pattern: .horizontalPull, primary: .shoulders, secondary: [.back], equipment: .cable, role: .isolation, startingWeightKg: 12),
        Exercise(id: "hs-iso-row", name: "Hammer Strength Iso Row", pattern: .horizontalPull, primary: .back, secondary: [.biceps], equipment: .machine, role: .compound, startingWeightKg: 25),
        Exercise(id: "t-bar-row", name: "T-Bar Row", pattern: .horizontalPull, primary: .back, secondary: [.biceps], equipment: .barbell, role: .compound, startingWeightKg: 30),
        Exercise(id: "machine-rear-delt-fly", name: "Machine Rear Delt Fly", pattern: .horizontalPull, primary: .shoulders, secondary: [.back], equipment: .machine, role: .isolation, startingWeightKg: 30),
        Exercise(id: "rack-pull", name: "Rack Pull", pattern: .hinge, primary: .back, secondary: [.hamstrings, .glutes], equipment: .barbell, role: .compound, startingWeightKg: 80),

        // Vertical push
        Exercise(id: "bb-ohp", name: "Overhead Press", pattern: .verticalPush, primary: .shoulders, secondary: [.triceps], equipment: .barbell, role: .compound, startingWeightKg: 30),
        Exercise(id: "db-shoulder-press", name: "Seated Dumbbell Shoulder Press", pattern: .verticalPush, primary: .shoulders, secondary: [.triceps], equipment: .dumbbell, role: .compound, startingWeightKg: 14),
        Exercise(id: "lateral-raise", name: "Dumbbell Lateral Raise", pattern: .lateralRaise, primary: .shoulders, equipment: .dumbbell, role: .isolation, startingWeightKg: 8),
        Exercise(id: "cable-lateral-raise", name: "Cable Lateral Raise", pattern: .lateralRaise, primary: .shoulders, equipment: .cable, role: .isolation, startingWeightKg: 5),
        Exercise(id: "machine-shoulder-press", name: "Machine Shoulder Press", pattern: .verticalPush, primary: .shoulders, secondary: [.triceps], equipment: .machine, role: .compound, startingWeightKg: 30),
        Exercise(id: "hs-shoulder-press", name: "Hammer Strength Shoulder Press", pattern: .verticalPush, primary: .shoulders, secondary: [.triceps], equipment: .machine, role: .compound, startingWeightKg: 15),
        Exercise(id: "machine-lateral-raise", name: "Machine Lateral Raise", pattern: .lateralRaise, primary: .shoulders, equipment: .machine, role: .isolation, startingWeightKg: 25),
        Exercise(id: "front-raise", name: "Dumbbell Front Raise", pattern: .lateralRaise, primary: .shoulders, equipment: .dumbbell, role: .isolation, startingWeightKg: 6),

        // Vertical pull
        Exercise(id: "pull-up", name: "Weighted Pull-Up", pattern: .verticalPull, primary: .back, secondary: [.biceps], equipment: .bodyweight, role: .compound, startingWeightKg: 0),
        Exercise(id: "chin-up", name: "Weighted Chin-Up", pattern: .verticalPull, primary: .biceps, secondary: [.back], equipment: .bodyweight, role: .compound, startingWeightKg: 0),
        Exercise(id: "lat-pulldown", name: "Lat Pulldown", pattern: .verticalPull, primary: .back, secondary: [.biceps], equipment: .cable, role: .accessory, startingWeightKg: 40),
        Exercise(id: "neutral-pull-up", name: "Neutral-Grip Pull-Up", pattern: .verticalPull, primary: .back, secondary: [.biceps], equipment: .bodyweight, role: .compound, startingWeightKg: 0),
        Exercise(id: "straight-arm-pulldown", name: "Straight-Arm Pulldown", pattern: .verticalPull, primary: .back, equipment: .cable, role: .isolation, startingWeightKg: 20),
        Exercise(id: "rear-delt-fly", name: "Rear Delt Fly", pattern: .horizontalPull, primary: .shoulders, secondary: [.back], equipment: .dumbbell, role: .isolation, startingWeightKg: 6),

        // Arms
        Exercise(id: "bb-curl", name: "Barbell Curl", pattern: .elbowFlexion, primary: .biceps, equipment: .barbell, role: .isolation, startingWeightKg: 15),
        Exercise(id: "incline-db-curl", name: "Incline Dumbbell Curl", pattern: .elbowFlexion, primary: .biceps, equipment: .dumbbell, role: .isolation, startingWeightKg: 8),
        Exercise(id: "hammer-curl", name: "Hammer Curl", pattern: .elbowFlexion, primary: .biceps, equipment: .dumbbell, role: .isolation, startingWeightKg: 10),
        Exercise(id: "skull-crusher", name: "Skull Crusher", pattern: .elbowExtension, primary: .triceps, equipment: .barbell, role: .isolation, startingWeightKg: 15),
        Exercise(id: "cable-pushdown", name: "Cable Triceps Pushdown", pattern: .elbowExtension, primary: .triceps, equipment: .cable, role: .isolation, startingWeightKg: 15),
        Exercise(id: "overhead-cable-ext", name: "Overhead Cable Extension", pattern: .elbowExtension, primary: .triceps, equipment: .cable, role: .isolation, startingWeightKg: 12),
        Exercise(id: "cable-curl", name: "Cable Curl", pattern: .elbowFlexion, primary: .biceps, equipment: .cable, role: .isolation, startingWeightKg: 15),
        Exercise(id: "db-curl", name: "Dumbbell Curl", pattern: .elbowFlexion, primary: .biceps, equipment: .dumbbell, role: .isolation, startingWeightKg: 10),
        Exercise(id: "machine-preacher-curl", name: "Machine Preacher Curl", pattern: .elbowFlexion, primary: .biceps, equipment: .machine, role: .isolation, startingWeightKg: 25),
        Exercise(id: "reverse-curl", name: "Reverse-Grip Curl", pattern: .elbowFlexion, primary: .forearms, secondary: [.biceps], equipment: .barbell, role: .isolation, startingWeightKg: 12),
        Exercise(id: "wrist-curl", name: "Wrist Curl", pattern: .wristFlexion, primary: .forearms, equipment: .barbell, role: .isolation, startingWeightKg: 12),
        Exercise(id: "reverse-wrist-curl", name: "Reverse Wrist Curl", pattern: .wristFlexion, primary: .forearms, equipment: .barbell, role: .isolation, startingWeightKg: 8),
        Exercise(id: "cable-wrist-curl", name: "Cable Wrist Curl", pattern: .wristFlexion, primary: .forearms, equipment: .cable, role: .isolation, startingWeightKg: 10),
    ]

    // MARK: Lower

    public static let lower: [Exercise] = [
        // Squat pattern
        Exercise(id: "bb-back-squat", name: "Barbell Back Squat", pattern: .squat, primary: .quads, secondary: [.glutes, .core], equipment: .barbell, role: .compound, startingWeightKg: 50, secondsPerRep: 4),
        Exercise(id: "bb-front-squat", name: "Front Squat", pattern: .squat, primary: .quads, secondary: [.core, .glutes], equipment: .barbell, role: .compound, startingWeightKg: 40, secondsPerRep: 4),
        Exercise(id: "hack-squat", name: "Hack Squat", pattern: .squat, primary: .quads, secondary: [.glutes], equipment: .machine, role: .compound, startingWeightKg: 60, secondsPerRep: 4),
        Exercise(id: "leg-press", name: "Leg Press", pattern: .squat, primary: .quads, secondary: [.glutes], equipment: .machine, role: .compound, startingWeightKg: 80),
        Exercise(id: "leg-extension", name: "Leg Extension", pattern: .squat, primary: .quads, equipment: .machine, role: .isolation, startingWeightKg: 30),
        Exercise(id: "kb-sumo-squat", name: "Kettlebell Sumo Squat", pattern: .squat, primary: .glutes, secondary: [.quads], equipment: .kettlebell, role: .accessory, startingWeightKg: 16),

        // Hinge
        Exercise(id: "bb-deadlift", name: "Barbell Deadlift", pattern: .hinge, primary: .hamstrings, secondary: [.glutes, .back, .core], equipment: .barbell, role: .compound, startingWeightKg: 60, secondsPerRep: 4),
        Exercise(id: "rdl", name: "Romanian Deadlift", pattern: .hinge, primary: .hamstrings, secondary: [.glutes, .back], equipment: .barbell, role: .compound, startingWeightKg: 50, secondsPerRep: 4),
        Exercise(id: "db-rdl", name: "Dumbbell Romanian Deadlift", pattern: .hinge, primary: .hamstrings, secondary: [.glutes], equipment: .dumbbell, role: .accessory, startingWeightKg: 20, secondsPerRep: 4),
        Exercise(id: "good-morning", name: "Good Morning", pattern: .hinge, primary: .hamstrings, secondary: [.glutes, .back], equipment: .barbell, role: .accessory, startingWeightKg: 25),
        Exercise(id: "leg-curl", name: "Seated Leg Curl", pattern: .hinge, primary: .hamstrings, equipment: .machine, role: .isolation, startingWeightKg: 30),
        Exercise(id: "nordic-curl", name: "Nordic Hamstring Curl", pattern: .hinge, primary: .hamstrings, equipment: .bodyweight, role: .isolation, startingWeightKg: 0, secondsPerRep: 5),
        Exercise(id: "lying-leg-curl", name: "Lying Leg Curl", pattern: .hinge, primary: .hamstrings, equipment: .machine, role: .isolation, startingWeightKg: 30),
        Exercise(id: "smith-rdl", name: "Smith Machine Romanian Deadlift", pattern: .hinge, primary: .hamstrings, secondary: [.glutes, .back], equipment: .smith, role: .compound, startingWeightKg: 40, secondsPerRep: 4),
        Exercise(id: "glute-ham-raise", name: "Glute Ham Raise", pattern: .hinge, primary: .hamstrings, secondary: [.glutes], equipment: .bodyweight, role: .isolation, startingWeightKg: 0, secondsPerRep: 4),
        Exercise(id: "back-extension", name: "Back Extension", pattern: .hinge, primary: .glutes, secondary: [.hamstrings, .back], equipment: .bodyweight, role: .isolation, startingWeightKg: 0),

        // Hip extension
        Exercise(id: "hip-thrust", name: "Barbell Hip Thrust", pattern: .hipExtension, primary: .glutes, secondary: [.hamstrings], equipment: .barbell, role: .compound, startingWeightKg: 60),
        Exercise(id: "cable-kickback", name: "Cable Glute Kickback", pattern: .hipExtension, primary: .glutes, equipment: .cable, role: .isolation, unilateral: true, startingWeightKg: 10),
        Exercise(id: "hip-abduction", name: "Seated Hip Abduction", pattern: .hipExtension, primary: .glutes, equipment: .machine, role: .isolation, startingWeightKg: 40),
        Exercise(id: "hip-adduction", name: "Seated Hip Adduction", pattern: .hipExtension, primary: .glutes, equipment: .machine, role: .isolation, startingWeightKg: 40),
        Exercise(id: "smith-glute-bridge", name: "Smith Machine Glute Bridge", pattern: .hipExtension, primary: .glutes, secondary: [.hamstrings], equipment: .smith, role: .compound, startingWeightKg: 40),

        // Lunge / unilateral
        Exercise(id: "bulgarian-split-squat", name: "Bulgarian Split Squat", pattern: .lunge, primary: .quads, secondary: [.glutes], equipment: .dumbbell, role: .accessory, unilateral: true, startingWeightKg: 12, secondsPerRep: 4),
        Exercise(id: "walking-lunge", name: "Walking Lunge", pattern: .lunge, primary: .glutes, secondary: [.quads], equipment: .dumbbell, role: .accessory, unilateral: true, startingWeightKg: 12),
        Exercise(id: "reverse-lunge", name: "Reverse Lunge", pattern: .lunge, primary: .glutes, secondary: [.quads, .hamstrings], equipment: .dumbbell, role: .accessory, unilateral: true, startingWeightKg: 12),
        Exercise(id: "step-up", name: "Dumbbell Step-Up", pattern: .lunge, primary: .glutes, secondary: [.quads], equipment: .dumbbell, role: .accessory, unilateral: true, startingWeightKg: 10),

        // Calves and core
        Exercise(id: "standing-calf-raise", name: "Standing Calf Raise", pattern: .calfRaise, primary: .calves, equipment: .machine, role: .isolation, startingWeightKg: 40),
        Exercise(id: "seated-calf-raise", name: "Seated Calf Raise", pattern: .calfRaise, primary: .calves, equipment: .machine, role: .isolation, startingWeightKg: 30),
        Exercise(id: "smith-calf-raise", name: "Smith Machine Calf Raise", pattern: .calfRaise, primary: .calves, equipment: .smith, role: .isolation, startingWeightKg: 40),
        Exercise(id: "machine-crunch", name: "Machine Crunch", pattern: .coreBrace, primary: .core, equipment: .machine, role: .isolation, startingWeightKg: 30),
        Exercise(id: "hanging-leg-raise", name: "Hanging Leg Raise", pattern: .coreBrace, primary: .core, equipment: .bodyweight, role: .isolation, startingWeightKg: 0),
        Exercise(id: "cable-crunch", name: "Cable Crunch", pattern: .coreBrace, primary: .core, equipment: .cable, role: .isolation, startingWeightKg: 25),
        Exercise(id: "ab-wheel", name: "Ab Wheel Rollout", pattern: .coreBrace, primary: .core, equipment: .bodyweight, role: .isolation, startingWeightKg: 0),
    ]
}
