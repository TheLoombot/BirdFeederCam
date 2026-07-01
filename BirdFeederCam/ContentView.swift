import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var camera = CameraMotionController()
    @State private var feederRect = CGRect(x: 0.28, y: 0.28, width: 0.44, height: 0.36) // normalized 0...1
    @Environment(\.openURL) private var openURL

    // Motion threshold range (lower threshold = more sensitive).
    private let minThreshold = 0.02
    private let maxThreshold = 0.20

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

            // Status panel: top-left.
            VStack {
                HStack(alignment: .top) {
                    statusCard
                    Spacer()
                }
                Spacer()
            }
            .padding()

            // Controls: Start/Stop + indicator in the lower-left.
            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    lowerLeftControls
                    Spacer()
                }
            }
            .padding()

            // Sensitivity: vertical slider on the right edge.
            HStack {
                Spacer()
                sensitivitySlider
            }
            .padding(.trailing)
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
        .frame(maxWidth: 220, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var lowerLeftControls: some View {
        HStack(spacing: 14) {
            Button {
                camera.isWatching ? camera.stop() : camera.start()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: camera.isWatching ? "stop.fill" : "play.fill")
                    Text(camera.isWatching ? "Stop" : "Start")
                }
                .font(.title2.weight(.bold))
                .frame(minWidth: 130)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            .controlSize(.large)
            .tint(camera.isWatching ? .red : .green)
            .shadow(radius: 4, y: 2)

            watchingBadge
        }
    }

    private var watchingBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(camera.isWatching ? Color.red : Color.secondary)
                .frame(width: 12, height: 12)
            Text(badgeText)
                .font(.subheadline.bold())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.thinMaterial)
        .clipShape(Capsule())
    }

    private var badgeText: String {
        if camera.isWatching { return "WATCHING" }
        return camera.isCameraLive ? "PAUSED" : "STARTING…"
    }

    private var sensitivitySlider: some View {
        VStack(spacing: 8) {
            Text("More")
                .font(.caption2)
                .foregroundStyle(.secondary)

            // A horizontal Slider rotated to vertical: up = higher sensitivity.
            Slider(value: sensitivityBinding, in: 0...1)
                .frame(width: 200)
                .rotationEffect(.degrees(-90))
                .frame(width: 44, height: 200)

            Text("Less")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text("Sensitivity")
                .font(.caption.bold())
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Maps the 0…1 slider (1 = top = most sensitive) to the underlying motion threshold
    /// (lower threshold = more sensitive).
    private var sensitivityBinding: Binding<Double> {
        Binding(
            get: { (maxThreshold - camera.motionThreshold) / (maxThreshold - minThreshold) },
            set: { camera.motionThreshold = maxThreshold - $0 * (maxThreshold - minThreshold) }
        )
    }

    private func openPhotosApp() {
        // iOS has no public API to open a specific album, so this opens the Photos app.
        if let url = URL(string: "photos-redirect://") {
            openURL(url)
        }
    }
}
