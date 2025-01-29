import SwiftUI

struct MainView: View {
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    var body: some View {
    
        VStack(spacing: 20) {
            
            Spacer()
            Text("Welcome to AR Space").font(.headline).padding()

            Button(action: {
                Task {
                    print("Entering immersive space")
                    await openImmersiveSpace(id: "ARView")
                }
            }) {
                Text("Enter Immersive Space")
                    .font(.title2)
                    .padding()
                    
            }
            Spacer()
        }
        .padding()
    }
}
