import SwiftUI

/// Swipe a row from the right towards the left to delete it.
///
/// The app's lists are `ScrollView`s, not `List`s (the Log is a ScrollView on
/// purpose — it groups sessions by month inside cards), so `.swipeActions` is
/// not available. This is the same interaction built by hand: a short drag
/// springs back, a decisive drag reveals the red Delete panel and fires
/// `onDelete` once. Callers decide whether that needs a confirmation — the Log
/// asks first, a set row does not (owner, 2026-09-25).
struct SwipeToDelete<Content: View>: View {
    /// Names the revealed Delete button for tests (`swipe-delete-<id>`).
    var id: String = "row"
    /// A full swipe past this deletes outright, the way a system row does.
    var fullSwipe: CGFloat = 160
    /// Fires once per completed swipe.
    var onDelete: () -> Void
    /// Fires on a tap that was not part of a swipe. nil = the content handles
    /// its own taps (a set row is all text fields).
    ///
    /// When this is set the tap and the swipe are ONE gesture. Every other
    /// shape failed on a scrolling row (2026-09-25): a NavigationLink swallowed
    /// the whole touch and navigated, and a separate tap gesture beat the drag
    /// so the row never moved. One gesture cannot outbid itself.
    var onTap: (() -> Void)?
    @ViewBuilder var content: Content

    @State private var offset: CGFloat = 0
    @State private var fired = false
    @State private var swiped = false

    private let limit: CGFloat = 150

    var body: some View {
        ZStack(alignment: .trailing) {
            if offset < 0 {
                // A partial swipe leaves this button exposed; a full swipe
                // fires the delete without a second touch.
                Button {
                    guard !fired else { return }
                    fired = true
                    onDelete()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                        Text("Delete")
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(maxHeight: .infinity)
                    .background(Palette.destructive)
                }
                .accessibilityIdentifier("swipe-delete-\(id)")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            }
            tappable
        }
        .clipped()
    }

    @ViewBuilder
    private var tappable: some View {
        if onTap == nil {
            row
        } else {
            row.accessibilityAddTraits(.isButton)
        }
    }

    private var row: some View {
        content
            // The sliding row has to be opaque, or the panel shows through it
            // on the way.
            .background(Palette.card)
            .offset(x: offset)
            .contentShape(Rectangle())
            .gesture(
                    // Distance 0 when the row has its own tap, so a tap is
                    // delivered to this gesture rather than to a second one.
                    DragGesture(minimumDistance: onTap == nil ? 18 : 0)
                        .onChanged { value in
                            let dx = value.translation.width
                            let dy = value.translation.height
                            // Left and clearly horizontal only: a vertical drag
                            // is the list scrolling.
                            guard dx < 0, abs(dx) > abs(dy) * 1.5 else { return }
                            swiped = true
                            offset = max(-limit, dx)
                        }
                        .onEnded { value in
                            if !swiped {
                                // Barely moved: a tap, not a swipe.
                                if abs(value.translation.width) < 12,
                                   abs(value.translation.height) < 12 {
                                    onTap?()
                                }
                                offset = 0
                                return
                            }
                            if offset <= -fullSwipe, !fired {
                                fired = true
                                withAnimation(.easeOut(duration: 0.18)) { offset = -limit }
                                onDelete()
                            } else if offset <= -40 {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    offset = -112
                                }
                            } else {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    offset = 0
                                }
                            }
                            // Hold taps off until the finger is up, so the
                            // release of a swipe cannot read as a tap.
                            Task {
                                try? await Task.sleep(nanoseconds: 350_000_000)
                                swiped = false
                            }
                        }
                )
    }
}
