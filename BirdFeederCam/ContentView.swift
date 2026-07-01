import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var camera = CameraMotionController()
    @State private var feederRect = CGRect(x: 0.28, y: 0.28, width: 0.44, height: 0.36) // normalized 0...1
    @Environment(\.openURL) private var openURL

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
                HStack(alignment: .top) {
                    statusCard
                    Spacer()
                    watchingBadge
                }
                .padding()

                Spacer()

                controlBar
            }
        }
        .overlay {
            // Unmistakable indicator that watching/saving is active.
            if camera.isWatching {
                Rectangle()
                    .strokeBorder(.red, lineWidth: 5)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            camera.watchRegion = feederRect
            camera.requestPermissionAndConfigure()
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Bird Feeder Cam")
                .font(.headline)
            Text(camera.statusText)
                .font(.subheadline)
            Text("Photos saved: \(camera.savedCount)")
                .font(.caption)

            Divider()

            Text("Saving to album")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(camera.albumName)
                .font(.caption.bold())
            Button {
                openPhotosApp()
            } label: {
                Label("Open in Photos", systemImage: "photo.on.rectangle.angled")
                    .font(.caption)
            }
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var watchingBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(camera.isWatching ? Color.red : Color.secondary)
                .frame(width: 12, height: 12)
            Text(badgeText)
                .font(.caption.bold())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.thinMaterial)
        .clipShape(Capsule())
    }

    private var badgeText: String {
        if camera.isWatching { return "WATCHING" }
        return camera.isCameraLive ? "PAUSED" : "STARTING…"
    }

    private var controlBar: some View {
        HStack(spacing: 12) {
            Button(camera.isWatching ? "Stop" : "Start") {
                camera.isWatching ? camera.stop() : camera.start()
            }
            .buttonStyle(.borderedProminent)
            .tint(camera.isWatching ? Color.red : Color.accentColor)

            Button("Test Save") {
                camera.saveCurrentFrameForTesting()
            }
            .buttonStyle(.bordered)

            VStack(spacing: 2) {
                Text(String(format: "Sensitivity (threshold): %.2f", camera.motionThreshold))
                    .font(.caption)
                    .monospacedDigit()
                Slider(value: $camera.motionThreshold, in: 0.02...0.20)
            }
            .frame(maxWidth: 260)
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding()
    }

    private func openPhotosApp() {
        // iOS has no public API to open a specific album, so this opens the Photos app.
        if let url = URL(string: "photos-redirect://") {
            openURL(url)
        }
    }
}
