@preconcurrency import AVFoundation
import Photos
import UIKit
import Combine

@MainActor
final class CameraMotionController: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published var statusText = "Waiting for camera permission"
    @Published var savedCount = 0
    @Published var isWatching = false
    @Published var isCameraLive = false
    @Published var motionThreshold: Double = 0.08 // lower = more sensitive

    var watchRegion = CGRect(x: 0.28, y: 0.28, width: 0.44, height: 0.36) // normalized preview coordinates

    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "BirdFeederCam.VideoFrames")
    private var previousSample: [UInt8]?
    private var lastSaveDate = Date.distantPast
    private let cooldownSeconds: TimeInterval = 8
    private var shutterPlayer: AVAudioPlayer?
    let albumName = "Bird Feeder Cam"

    func requestPermissionAndConfigure() {
        Task {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else {
                statusText = "Camera permission denied"
                return
            }
            configureSession()
            prepareShutterSound()
            startSession()
        }
    }

    /// Prepares the capture sound and routes it through the `.playback` audio session
    /// category so it is audible even when the ringer/silent switch is off.
    private func prepareShutterSound() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Non-fatal: if the session can't be configured we simply won't hear the sound.
        }
        // Prefer the genuine iOS camera-shutter sound; fall back to the bundled tone.
        // Playing it through an AVAudioPlayer (rather than AudioServicesPlaySystemSound)
        // means the .playback category applies, so it's heard even with the ringer off.
        let systemShutter = URL(fileURLWithPath: "/System/Library/Audio/UISounds/photoShutter.caf")
        let url = FileManager.default.fileExists(atPath: systemShutter.path)
            ? systemShutter
            : Bundle.main.url(forResource: "shutter", withExtension: "wav")
        if let url {
            shutterPlayer = try? AVAudioPlayer(contentsOf: url)
            shutterPlayer?.prepareToPlay()
        }
    }

    private func playShutter() {
        shutterPlayer?.currentTime = 0
        shutterPlayer?.play()
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            statusText = "Could not open rear camera"
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }

        if let connection = output.connection(with: .video) {
            if #available(iOS 17.0, *) {
                // 90° corresponds to landscapeRight for a back camera feed
                let angle: CGFloat = 90
                if connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
            } else if connection.isVideoOrientationSupported {
                connection.videoOrientation = .landscapeRight
            }
        }

        session.commitConfiguration()
    }

    /// Turns the camera on so the live preview appears immediately, independent of watching.
    private func startSession() {
        guard !session.isRunning else { return }
        queue.async { [session] in session.startRunning() }
        isCameraLive = true
        if !isWatching { statusText = "Ready" }
    }

    /// Arms motion watching: photos are saved when motion is detected inside the box.
    func start() {
        guard !isWatching else { return }
        isWatching = true
        lastSaveDate = .distantPast
        statusText = "Watching feeder region"
    }

    /// Disarms watching. The camera stays live so the preview keeps showing.
    func stop() {
        guard isWatching else { return }
        isWatching = false
        statusText = "Paused. Camera is live but not saving."
    }

    @MainActor private func handle(pixelBuffer: CVPixelBuffer) async {
        let sample = downsampleRegion(pixelBuffer: pixelBuffer, region: watchRegion, grid: 24)
        guard !sample.isEmpty else { return }

        defer { previousSample = sample }
        guard let previous = previousSample, previous.count == sample.count else { return }

        // The baseline keeps refreshing via the defer above; only evaluate/save while armed.
        guard isWatching else { return }

        var total = 0
        for i in sample.indices {
            total += abs(Int(sample[i]) - Int(previous[i]))
        }
        let averageDiff = Double(total) / Double(sample.count) / 255.0

        if averageDiff > motionThreshold, Date().timeIntervalSince(lastSaveDate) > cooldownSeconds {
            lastSaveDate = Date()
            let image = imageFromPixelBuffer(pixelBuffer)
            self.statusText = String(format: "Motion detected: %.3f", averageDiff)
            if let image { self.saveToPhotos(image) }
        }
    }

    private func saveToPhotos(_ image: UIImage) {
        // Adding to a custom album requires full read/write access, not add-only.
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            guard status == .authorized else {
                Task { @MainActor in
                    self.statusText = status == .limited
                        ? "Grant full Photos access to use the album"
                        : "Photos permission needed to save"
                }
                return
            }
            self.saveImage(image, toAlbumNamed: self.albumName)
        }
    }

    /// Saves the image into the named album, creating the album if it doesn't exist.
    /// (iOS keeps every asset in the main library too; the album is an additional grouping.)
    /// `nonisolated` so it can run from PhotoKit's background completion closures; it
    /// hops back to the main actor only to update the `@Published` state.
    private nonisolated func saveImage(_ image: UIImage, toAlbumNamed name: String) {
        func addAsset(to collection: PHAssetCollection?) {
            PHPhotoLibrary.shared().performChanges {
                let creation = PHAssetChangeRequest.creationRequestForAsset(from: image)
                if let collection,
                   let placeholder = creation.placeholderForCreatedAsset,
                   let albumChange = PHAssetCollectionChangeRequest(for: collection) {
                    albumChange.addAssets([placeholder] as NSArray)
                }
            } completionHandler: { success, error in
                Task { @MainActor in
                    if success {
                        self.savedCount += 1
                        self.statusText = "Saved to \"\(name)\" album"
                        self.playShutter()
                    } else {
                        self.statusText = "Save failed: \(error?.localizedDescription ?? "unknown error")"
                    }
                }
            }
        }

        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", name)
        let albums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)

        if let existing = albums.firstObject {
            addAsset(to: existing)
            return
        }

        // No album yet — create it, then add the asset.
        var placeholder: PHObjectPlaceholder?
        PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
            placeholder = request.placeholderForCreatedAssetCollection
        } completionHandler: { success, error in
            guard success, let id = placeholder?.localIdentifier else {
                Task { @MainActor in
                    self.statusText = "Could not create album: \(error?.localizedDescription ?? "unknown error")"
                }
                return
            }
            let created = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil)
            addAsset(to: created.firstObject)
        }
    }

    private func downsampleRegion(pixelBuffer: CVPixelBuffer, region: CGRect, grid: Int) -> [UInt8] {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return [] }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let ptr = base.assumingMemoryBound(to: UInt8.self)

        let x0 = max(0, min(width - 1, Int(region.minX * CGFloat(width))))
        let y0 = max(0, min(height - 1, Int(region.minY * CGFloat(height))))
        let x1 = max(x0 + 1, min(width, Int(region.maxX * CGFloat(width))))
        let y1 = max(y0 + 1, min(height, Int(region.maxY * CGFloat(height))))

        var result: [UInt8] = []
        result.reserveCapacity(grid * grid)

        for gy in 0..<grid {
            for gx in 0..<grid {
                let x = x0 + ((x1 - x0) * gx / grid)
                let y = y0 + ((y1 - y0) * gy / grid)
                let offset = y * bytesPerRow + x * 4
                let b = Int(ptr[offset])
                let g = Int(ptr[offset + 1])
                let r = Int(ptr[offset + 2])
                result.append(UInt8((r + g + b) / 3))
            }
        }
        return result
    }

    private func imageFromPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .right)
    }
}

extension CameraMotionController: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // Hop to the main actor to handle the pixel buffer without capturing it in a @Sendable closure
        Task { @MainActor in
            await self.handle(pixelBuffer: buffer)
        }
    }
}
