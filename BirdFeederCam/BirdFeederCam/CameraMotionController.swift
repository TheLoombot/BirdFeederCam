import AVFoundation
import Photos
import UIKit
import Combine

@MainActor
final class CameraMotionController: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published var statusText = "Waiting for camera permission"
    @Published var savedCount = 0
    @Published var isRunning = false
    @Published var motionThreshold: Double = 0.08 // lower = more sensitive

    var watchRegion = CGRect(x: 0.28, y: 0.28, width: 0.44, height: 0.36) // normalized preview coordinates

    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "BirdFeederCam.VideoFrames")
    private var previousSample: [UInt8]?
    private var currentImage: UIImage?
    private var lastSaveDate = Date.distantPast
    private let cooldownSeconds: TimeInterval = 8

    func requestPermissionAndConfigure() {
        Task {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else {
                statusText = "Camera permission denied"
                return
            }
            configureSession()
        }
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

        if let connection = output.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = .landscapeRight
        }

        session.commitConfiguration()
        statusText = "Ready. Drag the box over the feeder, then tap Start."
    }

    func start() {
        guard !session.isRunning else { return }
        isRunning = true
        statusText = "Watching feeder region"
        queue.async { [session] in session.startRunning() }
    }

    func stop() {
        guard session.isRunning else { return }
        isRunning = false
        statusText = "Stopped"
        queue.async { [session] in session.stopRunning() }
    }

    func saveCurrentFrameForTesting() {
        guard let image = currentImage else {
            statusText = "No frame yet"
            return
        }
        saveToPhotos(image)
    }

    private func handle(pixelBuffer: CVPixelBuffer) {
        let sample = downsampleRegion(pixelBuffer: pixelBuffer, region: watchRegion, grid: 24)
        guard !sample.isEmpty else { return }

        defer { previousSample = sample }
        guard let previous = previousSample, previous.count == sample.count else { return }

        var total = 0
        for i in sample.indices {
            total += abs(Int(sample[i]) - Int(previous[i]))
        }
        let averageDiff = Double(total) / Double(sample.count) / 255.0

        if averageDiff > motionThreshold, Date().timeIntervalSince(lastSaveDate) > cooldownSeconds {
            lastSaveDate = Date()
            let image = imageFromPixelBuffer(pixelBuffer)
            Task { @MainActor in
                self.statusText = String(format: "Motion detected: %.3f", averageDiff)
                self.currentImage = image
                if let image { self.saveToPhotos(image) }
            }
        }
    }

    private func saveToPhotos(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in self.statusText = "Photos permission needed to save" }
                return
            }
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            Task { @MainActor in
                self.savedCount += 1
                self.statusText = "Saved photo to Photos"
            }
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
        Task { @MainActor in self.handle(pixelBuffer: buffer) }
    }
}
