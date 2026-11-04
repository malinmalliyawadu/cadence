import SwiftUI

// MARK: Sessions open out of what was tapped

extension EnvironmentValues {
    /// The namespace a navigation stack zooms sessions open in, so a session grows out of the
    /// card or row that was tapped and shrinks back into it.
    @Entry var sessionZoom: Namespace.ID?
}

extension View {
    /// Marks this view as where `session` opens from, when its stack zooms sessions.
    func sessionZoomSource(_ session: TrainingSession, cornerRadius: CGFloat) -> some View {
        modifier(SessionZoomSource(id: session.id, cornerRadius: cornerRadius))
    }

    /// Hands the stack's namespace to the views below, and opens sessions pushed on it from their source.
    func zoomsSessions(in namespace: Namespace.ID) -> some View {
        environment(\.sessionZoom, namespace)
            .navigationDestination(for: TrainingSession.self) { session in
                SessionDetailView(session: session)
                    .navigationTransition(.zoom(sourceID: session.id, in: namespace))
            }
    }
}

private struct SessionZoomSource: ViewModifier {
    let id: TrainingSession.ID
    let cornerRadius: CGFloat
    @Environment(\.sessionZoom) private var namespace

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace) { source in
                source
                    .background(Palette.surface)
                    .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            }
        } else {
            content
        }
    }
}
