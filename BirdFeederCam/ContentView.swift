import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var camera = CameraMotionController()
    @State private var feederRect = CGRect(x: 0.28, y: 0.28, width: 0.44, height: 0.36) // normalized 0...1

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            GeometryReader { geo in
                FeederOverlay(rect: $feederRect, canvasSize: geo.size)
                    .onChange(of: feederRect) { _, newValue in
                        camera.watchRegion = newValue
                    }
            }

            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Bird Feeder Cam")
                            .font(.headline)
                        Text(camera.statusText)
                            .font(.subheadline)
                        Text("Photos saved: \(camera.savedCount)")
                            .font(.caption)
                    }
                    .padding(12)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Spacer()
                }
                .padding()

                Spacer()

                HStack(spacing: 12) {
                    Button(camera.isRunning ? "Stop" : "Start") {
                        camera.isRunning ? camera.stop() : camera.start()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Test Save") {
                        camera.saveCurrentFrameForTesting()
                    }
                    .buttonStyle(.bordered)

                    Slider(value: $camera.motionThreshold, in: 0.02...0.20) {
                        Text("Sensitivity")
                    }
                    .frame(maxWidth: 260)
                }
                .padding(12)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding()
            }
        }
        .onAppear {
            camera.watchRegion = feederRect
            camera.requestPermissionAndConfigure()
        }
    }
}
