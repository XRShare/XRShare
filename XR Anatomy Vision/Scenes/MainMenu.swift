//
//  MainMenu.swift
//  XR Anatomy
//
//  Created by Marko Vujic on 2024-12-10.
//

import SwiftUI


struct MainMenu: View {
    @Environment(AppModel.self) private var appModel

    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    var body: some View {
        VStack {
            Image("logo_white")
            HStack {
                Button {
                    appModel.currentPage = .joinSession
                } label: {
                    Text("Join a Session")
                        .padding(.horizontal, 120)
                        .padding(.vertical, 50)

                }
                .animation(.none, value: 0)
                .font(.system(size: 40))
                .fontWeight(.bold)

                Button {
                    Task { @MainActor in
                        let res = await openImmersiveSpace(id: appModel.immersiveSpaceID)
                        if (res == .opened) {
                            print("immersive space opened")
                        }
                        if (res == .error) {
                            print("error opening immersive space")
                        }
                        if (res == .userCancelled) {
                            print("user canceled")
                        }
                        appModel.currentPage = .inSession
                    }
                } label: {
                    Text("Host a session")
                        .padding(.horizontal, 120)
                        .padding(.vertical, 50)
                }
                .animation(.none, value: 0)
                .font(.system(size: 40))
                .fontWeight(.bold)
            }
        }
    }
}
#Preview(windowStyle: .volumetric) {
    MainMenu()
        .environment(AppModel())
}
