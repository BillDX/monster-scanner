import SwiftUI

/// The consent gate (first launch, and from Settings).
struct ConsentView: View {
    var onAccept: () -> Void
    var showsClose = false
    @Environment(\.dismiss) private var dismiss
    @State private var showingHowItWorks = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Stamp(text: "TOP SECRET")
            Text("BEFORE YOU SCAN")
                .font(Theme.mono(.title2, weight: .bold))
                .foregroundStyle(Theme.neon)
                .crtGlow()
            VStack(spacing: 14) {
                Text("Only scan people who said yes.")
                Text("Photos never leave this phone.")
            }
            .font(Theme.mono(.body))
            .foregroundStyle(Theme.neon)
            .multilineTextAlignment(.center)

            Text("It's a toy. Scanner readings may be wildly inaccurate.")
                .font(Theme.mono(.footnote))
                .foregroundStyle(Theme.dimNeon)
                .multilineTextAlignment(.center)
            Spacer()
            VStack(spacing: 14) {
                Button("I promise") {
                    onAccept()
                    if showsClose { dismiss() }
                }
                .buttonStyle(NeonButtonStyle(filled: true))
                Button("Read how it works") { showingHowItWorks = true }
                    .buttonStyle(NeonButtonStyle())
            }
        }
        .padding(24)
        .crtScreen()
        .sheet(isPresented: $showingHowItWorks) { HowItWorksView() }
    }
}

struct HowItWorksView: View {
    @Environment(\.dismiss) private var dismiss

    private let sections: [(String, String)] = [
        ("WHAT IT LOOKS AT",
         "Clothing colours, accessories, the setting, head tilt, how close you are to the camera, the time, the moon and your battery. Never skin, body shape, weight, ethnicity, health or looks."),
        ("WHO DECIDES",
         "Plain code picks the verdict from those clues, plus a sprinkle of seeded randomness. The same photo gets the same verdict until you ask for a Second Opinion."),
        ("WHERE YOUR PHOTO GOES",
         "Nowhere. It's analysed on this iPhone, kept in memory only, and forgotten when you scan again. No uploads, no accounts, no face recognition."),
        ("HOW ACCURATE IT IS",
         "Not at all. It's a party game. Scanner readings may be wildly inaccurate."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(sections, id: \.0) { title, text in
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: title)
                            Text(text)
                                .font(Theme.mono(.callout))
                                .foregroundStyle(Theme.neon.opacity(0.9))
                        }
                    }
                }
                .padding(20)
            }
            .crtScreen()
            .navigationTitle("How it works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
