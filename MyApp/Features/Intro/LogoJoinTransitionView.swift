import SwiftUI

/// The brand transition shown right after the intro video closes: "IRON" slides in from the left
/// and "MAN" from the right to meet in the middle, "PROJECT" rises in beneath them, then a red
/// flash expands to fill the whole screen and fades away to reveal the app underneath.
struct LogoJoinTransitionView: View {
    let onFinished: () -> Void

    private enum Step {
        case start, joined, projectShown, flashing, revealing
    }

    @State private var step: Step = .start
    @State private var flashScale: CGFloat = 0.02

    private var textVisible: Bool { step != .flashing && step != .revealing }
    private var projectVisible: Bool { step == .projectShown || step == .flashing }
    private var flashVisible: Bool { step == .flashing || step == .revealing }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 10) {
                HStack(spacing: 2) {
                    Text("IRON")
                        .offset(x: step == .start ? -260 : 0)
                    Text("MAN")
                        .offset(x: step == .start ? 260 : 0)
                }
                .font(.system(size: 46, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

                Text("PROJECT")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .tracking(8)
                    .foregroundStyle(Color.accentColor)
                    .opacity(projectVisible ? 1 : 0)
                    .offset(y: projectVisible ? 0 : 26)
            }
            .opacity(textVisible ? 1 : 0)

            // The "total expansion": a small red dot that scales up until it floods the screen,
            // then the whole view fades to reveal the app mounted underneath.
            Circle()
                .fill(Color.accentColor)
                .frame(width: 60, height: 60)
                .scaleEffect(flashScale)
                .opacity(flashVisible ? 1 : 0)
        }
        .ignoresSafeArea()
        .opacity(step == .revealing ? 0 : 1)
        .onAppear(perform: runSequence)
    }

    private func runSequence() {
        withAnimation(.easeOut(duration: 0.55)) {
            step = .joined
        }
        after(0.55) {
            // IRON and MAN land in the middle right about here.
            Haptics.medium()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                step = .projectShown
            }
        }
        after(1.05) {
            // The total expansion — the biggest beat in the sequence gets the strongest thump.
            Haptics.heavy()
            step = .flashing
            withAnimation(.easeIn(duration: 0.4)) {
                flashScale = 45
            }
        }
        after(1.55) {
            withAnimation(.easeOut(duration: 0.4)) {
                step = .revealing
            }
        }
        after(1.95, action: onFinished)
    }

    private func after(_ seconds: Double, action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: action)
    }
}

#Preview {
    LogoJoinTransitionView {}
}
