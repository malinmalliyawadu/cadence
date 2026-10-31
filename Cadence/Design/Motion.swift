import SwiftUI

/// How things move. Springs throughout, critically damped, so a value starts from wherever it is
/// on screen and never overshoots: nothing here was thrown, it was tapped. Short, because most of
/// what moves is touched dozens of times a session. Motion only says where something came from,
/// that a tap landed, or that a number changed; it never decorates.
enum Motion {
    /// A press landing: chips, steppers, rows.
    static let press = Animation.spring(duration: 0.16, bounce: 0)
    /// A value changing in place: a number stepping, a bar or ring filling, a selection sliding.
    static let settle = Animation.spring(duration: 0.3, bounce: 0)
    /// Something opening in the flow of the page: a movement expanding, a set's editor.
    static let reveal = Animation.spring(duration: 0.36, bounce: 0)
    /// Something leaving. A third quicker than it came, since the athlete has already moved on.
    static let exit = Animation.spring(duration: 0.24, bounce: 0)
}

extension AnyTransition {
    /// Opens in place, settling a few points down from where it starts; closes with a quicker fade.
    static var reveal: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: -8)).animation(Motion.reveal),
            removal: .opacity.animation(Motion.exit)
        )
    }

    /// Rises from the bottom edge and drops back the way it came. Fades only under Reduce Motion.
    static func rise(reduceMotion: Bool) -> AnyTransition {
        let travel: AnyTransition = reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
        return .asymmetric(insertion: travel.animation(Motion.reveal), removal: travel.animation(Motion.exit))
    }
}

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
