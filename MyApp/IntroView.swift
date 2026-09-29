import SwiftUI

/// Full-screen looping intro video with a glowing "Continuar" button over it, shown once per app
/// launch — mirrors the platform's own landing page (`ironman_intro.mp4` + its "Enter" button).
struct IntroView: View {
    let onContinue: () -> Void

    @State private var isGlowing = false
    @State private var showContent = false
    @State private var isMuted = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            LoopingVideoBackground(resource: "ironman_intro", fileExtension: "mp4", isMuted: isMuted)
                .ignoresSafeArea()

            // Darkens the edges and centre band so the title stays readable over any frame.
            RadialGradient(
                colors: [.black.opacity(0.25), .black.opacity(0.55), .black.opacity(0.85)],
                center: .center,
                startRadius: 60,
                endRadius: 520
            )
            .ignoresSafeArea()

            VStack(spacing: 48) {
                VStack(spacing: 4) {
                    Text("BEM-VINDO AO")
                        .font(.subheadline.weight(.semibold))
                        .tracking(6)
                        .foregroundStyle(.white.opacity(0.8))
                    Text("IRONMAN PROJECT")
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                    Text("2027")
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                }
                .shadow(color: .black.opacity(0.6), radius: 20, y: 4)
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 16)

                Button {
                    Haptics.medium()
                    onContinue()
                } label: {
                    Text("CONTINUAR")
                        .font(.title3.weight(.bold))
                        .tracking(4)
                        .foregroundStyle(.white)
                        .padding(.vertical, 18)
                        .padding(.horizontal, 56)
                        .background(
                            Capsule().fill(
                                LinearGradient(
                                    colors: [Color(red: 1, green: 0.14, blue: 0.28), Color.accentColor, Color(red: 0.66, green: 0, blue: 0.12)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        )
                        .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                        .shadow(color: Color.accentColor.opacity(isGlowing ? 0.75 : 0.35), radius: isGlowing ? 24 : 10)
                }
                .buttonStyle(.plain)
                .scaleEffect(showContent ? 1 : 0.9)
                .opacity(showContent ? 1 : 0)
            }
            .padding(.horizontal, 24)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                Haptics.light()
                isMuted.toggle()
            } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.35), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .padding(.trailing, 20)
            .opacity(showContent ? 1 : 0)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
                showContent = true
            }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                isGlowing = true
            }
        }
    }
}

#Preview {
    IntroView {}
}
