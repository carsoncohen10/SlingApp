import SwiftUI

struct LoadingScreenView: View {
    @State private var logoScale: CGFloat = 0.8
    @State private var logoOpacity: Double = 0.0
    @State private var drawingProgress: CGFloat = 0.0
    
    var body: some View {
        ZStack {
            // Simple solid white background
            Color.white
                .ignoresSafeArea()
            
            // Centered animated logo matching the sign in/sign up design
            ZStack {
                // Background rounded square (squircle) with sling gradient
                RoundedRectangle(cornerRadius: 30)
                    .fill(Color.slingGradient)
                    .frame(width: 120, height: 120)
                    .shadow(color: Color.slingBlue.opacity(0.3), radius: 12, x: 0, y: 6)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
                
                // Animated line chart with arrow - using exact vector path
                Path { path in
                    // Original SVG path data
                    path.move(to: CGPoint(x: 31.0002, y: 315.673))
                    path.addLine(to: CGPoint(x: 178.673, y: 168))
                    path.addLine(to: CGPoint(x: 336.112, y: 253.175))
                    path.addLine(to: CGPoint(x: 621, y: 31))
                    // Arrow part
                    path.addLine(to: CGPoint(x: 437.939, y: 31)) // H437.939
                    path.move(to: CGPoint(x: 621, y: 31)) // M621 31
                    path.addLine(to: CGPoint(x: 621, y: 209)) // V209 (doubled from 120 to 209)
                }
                .trim(from: 0, to: drawingProgress)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 35, lineCap: .round, lineJoin: .round))
                .scaleEffect(0.12)
                .offset(x: -18, y: 28)
                .opacity(logoOpacity)
            }
        }
        .onAppear {
            // Logo entrance animation
            withAnimation(.easeOut(duration: 0.8)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            
            // Drawing animation after logo appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeInOut(duration: 1.2)) {
                    drawingProgress = 1.0
                }
            }
        }
    }
}

#Preview {
    LoadingScreenView()
}
