import SwiftUI

/// A session on its own screen. The tab bar stays: hiding it here made it reappear with a jump
/// once the zoom back to Home had finished, and it minimises on scroll anyway.
struct SessionDetailView: View {
    let session: TrainingSession

    var body: some View {
        switch session.modality {
        case .strength: StrengthSessionView(session: session)
        case .running, .yoga: SimpleSessionView(session: session)
        }
    }
}
