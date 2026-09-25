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
    /// How far the row has to travel before the delete fires.
    var threshold: CGFloat = 110
    /// Fires once per completed swipe.
    var onDelete: () -> Void
    @ViewBuilder var content: Content

    @State private var offset: CGFloat = 0
    @State private var fired = false

    private let limit: CGFloat = 150

    var body: some View {
        ZStack(alignment: .trailing) {
            if offset < 0 {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                    Text("Delete")
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.trailing, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .background(Palette.destructive)
            }
            content
                // The sliding row has to be opaque, or the panel shows through
                // it on the way.
                .background(Palette.card)
                .offset(x: offset)
                .gesture(
                    DragGesture(minimumDistance: 18)
                        .onChanged { value in
                            let dx = value.translation.width
                            // Left only, and never beyond the limit.
                            guard dx < 0 else { return }
                            offset = max(-limit, dx)
                        }
                        .onEnded { _ in
                            if offset <= -threshold, !fired {
                                fired = true
                                withAnimation(.easeOut(duration: 0.18)) { offset = -limit }
                                onDelete()
                            } else {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    offset = 0
                                }
                            }
                        }
                )
        }
        .clipped()
    }
}
