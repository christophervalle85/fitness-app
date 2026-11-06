import Foundation
import Testing
@testable import Weekform

struct WorkoutPickerTests {
    @Test func changingUnitsPreservesStartingLoad() {
        var exercise = PlanExercise(startingLoad: 100, loadUnit: "lb")
        exercise.selectWorkoutLoadUnit("kg")
        #expect(abs((exercise.startingLoad ?? 0) - 45.359237) < 0.000001)
        #expect(exercise.loadUnit == "kg")
        exercise.selectWorkoutLoadUnit("lb")
        #expect(abs((exercise.startingLoad ?? 0) - 100) < 0.000001)
        exercise.selectWorkoutLoadUnit("lb")
        #expect(abs((exercise.startingLoad ?? 0) - 100) < 0.000001)
    }

    @Test func changingMethodClearsIncomparableStartingLoad() {
        var exercise = PlanExercise(startingLoad: 25)
        exercise.changeWorkoutBasis(from: .assisted, to: .assisted)
        #expect(exercise.startingLoad == 25)
        exercise.changeWorkoutBasis(from: .assisted, to: .added)
        #expect(exercise.startingLoad == nil)
        #expect(LoadBasis(exercise) == .added)
        exercise.selectWorkoutLoadUnit("kg")
        #expect(exercise.startingLoad == nil)
    }

    @Test func elapsedDurationAvoidsIntegerOverflow() {
        #expect(elapsedString(90.9) == "1:30")
        #expect(elapsedString(-1) == "0:00")
        #expect(elapsedString(.infinity) == "0:00")
        #expect(elapsedString(.nan) == "0:00")
        #expect(elapsedString(4_000_000_000) == "66666666:40")
        #expect(elapsedString(TimeInterval(Int.max)) == "\(Int.max / 60):07")
    }
}
