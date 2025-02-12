import SwiftUI

struct MainView: View {
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Welcome to AR Space").font(.headline).padding()
            Button("Enter Immersive Space") {
                Task {
                    await openImmersiveSpace(id: "ARView")
                }
            }
            .font(.title2)
            .padding()
            Spacer()
        }
        .padding()
    }
}
