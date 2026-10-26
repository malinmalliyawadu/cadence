import SwiftUI

struct SessionDetailView: View {
    let session: TrainingSession

    var body: some View {
        switch session.modality {
        case .strength: StrengthSessionView(session: session)
        case .running, .yoga: SimpleSessionView(session: session)
        }
    }
}
