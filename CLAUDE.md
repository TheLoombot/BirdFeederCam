# CLAUDE.md — BirdFeederCam

Guidance for Claude Code (and humans) working in this repository.

## What this is

**BirdFeederCam** is a small native iPadOS app (SwiftUI + AVFoundation) that turns
an iPad into a motion-triggered bird-feeder camera. You point the rear camera at a
feeder, drag a box over the part of the frame you care about, and the app saves a
photo to the Photos library whenever it detects enough movement inside that box.

It is deliberately a **first-pass / prototype**: motion is detected by raw
pixel-difference, not by any bird/object recognition. The README explicitly flags
Vision / Core ML bird recognition as future work.

- Platform: iPadOS (rear `builtInWideAngleCamera`, landscape-right orientation)
- UI: SwiftUI
- Capture: AVFoundation (`AVCaptureSession` with a video-data output)
- Persistence: writes JPEGs to the user's Photos library via `Photos` / `UIKit`
- No backend, no network, no third-party dependencies, no tests.

## Functional overview (what the user sees)

- **Live preview** fills the screen.
- A **draggable yellow box** ("Drag box over feeder") marks the watch region.
  Only this region is monitored for motion.
- A status card (top-left) shows current state and a running **"Photos saved"** count.
- Bottom control bar:
  - **Start / Stop** — begins/ends the capture session and motion watching.
  - **Test Save** — saves the most recent frame immediately (used to confirm
    Photos permissions work).
  - **Sensitivity slider** — adjusts the motion threshold (0.02–0.20; lower = more sensitive).
- When motion in the box exceeds the threshold (and a cooldown has elapsed), the app
  captures the frame and saves it to Photos, updating the status and count.

## Architecture / file map

All source lives in `BirdFeederCam/BirdFeederCam/`:

| File | Role |
|------|------|
| `BirdFeederCamApp.swift` | `@main` App entry point; hosts `ContentView` in a `WindowGroup`. |
| `ContentView.swift` | Root view. Composes the camera preview, draggable overlay, status card, and control bar. Owns the `CameraMotionController` (`@StateObject`) and the normalized feeder rect. |
| `CameraMotionController.swift` | The core. `@MainActor ObservableObject` that owns the `AVCaptureSession`, requests permissions, runs motion detection on each frame, and saves photos. |
| `CameraPreview.swift` | `UIViewRepresentable` wrapper exposing an `AVCaptureVideoPreviewLayer`-backed `UIView` to SwiftUI. |
| `FeederOverlay.swift` | The draggable yellow watch-region box. Operates in normalized (0…1) coordinates, scaled to the canvas size. |
| `Info.plist` | Declares `NSCameraUsageDescription` and `NSPhotoLibraryAddUsageDescription`. |
| `README.md` | End-user setup/run instructions and suggested iPad settings. |

### How motion detection works (technical)

In `CameraMotionController`:

1. The capture session uses `.photo` preset, BGRA pixel format,
   `alwaysDiscardsLateVideoFrames = true`, and delivers frames on a private
   `DispatchQueue` ("BirdFeederCam.VideoFrames").
2. For each frame (`captureOutput`), the pixel buffer is hopped to the main actor and
   passed to `handle(pixelBuffer:)`.
3. `downsampleRegion(...)` locks the buffer and samples a **24×24 grid** of grayscale
   values (`(r+g+b)/3`) from inside the normalized `watchRegion`.
4. The mean absolute per-cell difference vs. the previous frame's grid is normalized to
   0…1 (`averageDiff`).
5. If `averageDiff > motionThreshold` **and** more than `cooldownSeconds` (8s) have
   passed since the last save, the full frame is rendered to a `UIImage`
   (`CIImage` → `CIContext.createCGImage`) and saved via
   `UIImageWriteToSavedPhotosAlbum`.
6. Photos add-only authorization is requested lazily at first save.

Coordinates: `watchRegion` / `feederRect` are normalized `CGRect`s (0…1). `FeederOverlay`
multiplies by the canvas size to draw, and clamps dragging so the box stays on-screen.

## Known rough edges / gotchas

- **Duplicate Xcode project layout.** There are two `.xcodeproj` bundles:
  `./BirdFeederCam.xcodeproj` (original) and `./BirdFeederCam/BirdFeederCam.xcodeproj`
  (added when the source was reorganized into the nested `BirdFeederCam/BirdFeederCam/`
  folder). Confirm which one actually builds the current source before relying on it;
  consider consolidating to a single project.
- `Info.plist` keys are also expected to be set in the Xcode target (the README has you
  add them manually). The standalone `Info.plist` here documents the required keys.
- Motion detection is naive pixel-difference — lighting changes, shadows, and wind will
  trigger false saves. The 8s cooldown is the only debounce.
- No persistence of settings, no in-app gallery, no recognition/labeling.

## Conventions for changes

- Keep the controller `@MainActor`; the capture delegate callback is `nonisolated` and
  hops to the main actor — preserve that pattern when touching frame handling.
- Work in normalized coordinates for any region/overlay logic.
- No external dependencies have been introduced; prefer staying dependency-free unless
  adding recognition (Vision / Core ML) as the README anticipates.

## Building / running

There is no command-line build set up. Open the project in Xcode, ensure the camera and
Photos usage descriptions are present in the target's Info settings, target iPadOS 17+,
and run on a physical iPad (camera APIs do not work in the Simulator).
See `BirdFeederCam/BirdFeederCam/README.md` for step-by-step setup.
