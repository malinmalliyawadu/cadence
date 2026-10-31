import SwiftUI

/// A session on its own screen, without the tab bar: in the gym the screen belongs to the session,
/// and the rest card takes the bottom edge.
struct SessionDetailView: View {
    let session: TrainingSession

    var body: some View {
        Group {
            switch session.modality {
            case .strength: StrengthSessionView(session: session)
            case .running, .yoga: SimpleSessionView(session: session)
            }
        }
        .toolbarVisibility(.hidden, for: .tabBar)
    }
}
