import SwiftUI

struct SessionNameInputAlert: View {
    @Binding var isPresented: Bool
    @Binding var sessionName: String
    var onComplete: () -> Void

    var body: some View {
        if isPresented {
            ZStack {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        isPresented = false
                    }

                VStack(spacing: 20) {
                    Text("Enter Session Name")
                        .font(.headline)
                    
                    TextField("Session Name", text: $sessionName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(.horizontal)
                    
                    HStack {
                        Button("Cancel") {
                            isPresented = false
                        }
                        .padding(.horizontal)

                        Button("OK") {
                            isPresented = false
                            onComplete()
                        }
                        .padding(.horizontal)
                    }
                }
                .padding()
                .background(Color.white)
                .cornerRadius(10)
                .shadow(radius: 10)
                .padding(.horizontal, 40)
            }
        }
    }
}
