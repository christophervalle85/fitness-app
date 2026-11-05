import ActivityKit
import AppIntents
import Foundation

struct FoundationActivity: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var confirmed: Bool
    }

    // This development probe contains exactly one synthetic set.
    static let commandID = UUID(uuidString: "151DABE3-E151-4A8C-91D6-EFD49335382A")!
    static let reps = 8

    static func publishConfirmation() async {
        let content = ActivityContent(state: ContentState(confirmed: true), staleDate: nil)
        for activity in Activity<Self>.activities {
            await activity.update(content)
        }
    }
}

#if WEEKFORM_DEVELOPMENT
struct ConfirmTestSet: LiveActivityIntent {
    static var title: LocalizedStringResource = "Confirm test set"
    static var isDiscoverable: Bool { false }

    func perform() async throws -> some IntentResult {
        try FoundationStore.live().confirm(id: FoundationActivity.commandID, reps: FoundationActivity.reps)
        await FoundationActivity.publishConfirmation()
        return .result()
    }
}
#endif
