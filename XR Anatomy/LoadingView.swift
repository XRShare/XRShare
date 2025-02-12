//
//  LoadingView.swift
//  XR Anatomy
//
//  Created by Ali Kara on 2025-02-12.
//


import SwiftUI

struct LoadingView: View {
    @Binding var loadingProgress: Float
    var showProgress: Bool = true

    var body: some View {
        ZStack {
            Color(red: 0.9137, green: 0.9176, blue: 0.9255)
                .edgesIgnoringSafeArea(.all)
            VStack(spacing: 20) {
                Image("logo_white")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 360)
                    .padding(.top, 40)

                Text("Preparing your AR experience...")
                    .font(Font.custom("Courier New", size: 18))
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.top,35)

                if showProgress {
                    ProgressView(value: loadingProgress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(width: 200)
                        .padding(.top,20)
                        .tint(.black)

                    if loadingProgress < 1.0 {
                        Text("Loading models and initializing AR...")
                            .font(Font.custom("Courier New", size: 14))
                            .foregroundColor(.black)
                            .padding(.top,10)
                    }
                }
                Spacer()
            }
            .padding()
        }
        .onAppear {
            OrientationManager.shared.lock(to: .portrait)
        }
    }
}