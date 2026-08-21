import SwiftUI

/// The crest on black, continuing from the native launch screen.
///
/// The `UILaunchScreen` entry in Info.plist draws the same image at the same
/// size before any code runs, so this appears to be the same screen — it just
/// gains a subtle scale and then fades away. Without the native launch screen
/// underneath, iOS would show a white window first and the effect would break.
struct SplashView: View {
    /// Matches `UIImageName: LaunchLogo`, whose asset is authored at 280pt.
    static let logoSize: CGFloat = 280

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false

    var body: some View {
        ZStack {
            // Matches the artwork's own field exactly, so the crest reads as
            // part of the screen rather than a square pasted onto it.
            Color.crestField.ignoresSafeArea()

            Image("LaunchLogo")
                .resizable()
                .scaledToFit()
                .frame(width: Self.logoSize, height: Self.logoSize)
                .scaleEffect(settled || reduceMotion ? 1.04 : 1.0)
        }
        .accessibilityElement()
        .accessibilityLabel("Commissioners Cartel")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.1)) { settled = true }
        }
    }
}

#Preview {
    SplashView()
}
