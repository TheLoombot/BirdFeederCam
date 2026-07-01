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

- **Live preview** fills the screen and turns on **automatically at launch** (right
  after camera permission is granted) — the camera does not wait for the Start button.
- A **draggable yellow box** ("Drag box over feeder") marks the watch region.
  Only this region is monitored for motion.
- A compact status card (top-left) shows current state, a running **"Photos saved"**
  count, the destination **album name**, and an **Open in Photos** button.
- **Lower-left controls:** a large **Start / Stop** button (green Start / red Stop) with
  a **"WATCHING" / "PAUSED" badge** right beside it. A **red border around the whole
  screen** also appears while armed. (Camera-live vs. armed are distinct states: the
  preview is always live; Start/Stop only toggles saving.)
- **Vertical sensitivity slider** on the right edge — **up = more sensitive**, down =
  less. Labeled "Sensitivity" ("More"/"Less" at the ends); the numeric value is not
  shown. It maps inversely to the underlying motion threshold (0.02–0.20; lower = more
  sensitive) via a computed `Binding` in `ContentView`.
- When armed and motion in the box exceeds the threshold (and a cooldown has elapsed),
  the app captures the frame, saves it into a **"Bird Feeder Cam" album** in Photos,
  and plays a **capture sound** (see below).
- **Capture sound:** the genuine iOS camera shutter (`/System/Library/Audio/UISounds/
  photoShutter.caf`) played via `AVAudioPlayer` under the **`.playback`** audio-session
  category, so it's audible **even with the ringer/silent switch off**. Falls back to a
  bundled `shutter.wav` tone if the system file is unavailable. (Played through
  `AVAudioPlayer` rather than `AudioServicesPlaySystemSound` specifically so the
  mute-ignoring `.playback` category applies.)
- **Open in Photos** opens the Photos app — iOS has no public API to deep-link to a
  specific album, so it can't jump straight to "Bird Feeder Cam".

## Repository layout

Standard single-project Xcode layout at the repo root:

```
BirdFeederCam.xcodeproj/      # the Xcode project
BirdFeederCam/                # app source (the target's synchronized folder)
CLAUDE.md, .gitignore, ...
```

## Architecture / file map

All source lives in `BirdFeederCam/`:

| File | Role |
|------|------|
| `BirdFeederCamApp.swift` | `@main` App entry point; hosts `ContentView` in a `WindowGroup`. |
| `ContentView.swift` | Root view. Composes the camera preview, draggable overlay, status card, and control bar. Owns the `CameraMotionController` (`@StateObject`) and the normalized feeder rect. |
| `CameraMotionController.swift` | The core. `@MainActor ObservableObject` that owns the `AVCaptureSession`, requests permissions, runs motion detection on each frame, saves photos, and plays the capture sound. |
| `shutter.wav` | Fallback capture tone (generated) used only if the system shutter `.caf` is unavailable. Bundled automatically by the synchronized group. |
| `CameraPreview.swift` | `UIViewRepresentable` wrapper exposing an `AVCaptureVideoPreviewLayer`-backed `UIView` to SwiftUI. |
| `FeederOverlay.swift` | The draggable yellow watch-region box. Operates in normalized (0…1) coordinates, scaled to the canvas size. |
| `Info.plist` | Declares `NSCameraUsageDescription` and `NSPhotoLibraryAddUsageDescription`. |
| `README.md` | End-user setup/run instructions and suggested iPad settings. |

### How motion detection works (technical)

In `CameraMotionController`:

1. The capture session uses `.photo` preset, BGRA pixel format,
   `alwaysDiscardsLateVideoFrames = true`, and delivers frames on a private
   `DispatchQueue` ("BirdFeederCam.VideoFrames").
   The session is started as soon as `configureSession()` finishes (`startSession()`),
   so the preview is live at launch regardless of the Start button.
2. For each frame (`captureOutput`), the pixel buffer is hopped to the main actor and
   passed to `handle(pixelBuffer:)`. The grayscale baseline (`previousSample`) refreshes
   every frame, but motion is only evaluated/saved while armed (`guard isWatching`) —
   so Start/Stop gates *saving*, not the camera feed.
3. `downsampleRegion(...)` locks the buffer and samples a **24×24 grid** of grayscale
   values (`(r+g+b)/3`) from inside the normalized `watchRegion`.
4. The mean absolute per-cell difference vs. the previous frame's grid is normalized to
   0…1 (`averageDiff`).
5. If `averageDiff > motionThreshold` **and** more than `cooldownSeconds` (8s) have
   passed since the last save, the full frame is rendered to a `UIImage`
   (`CIImage` → `CIContext.createCGImage`) and saved into the **"Bird Feeder Cam"
   album** (`saveImage(_:toAlbumNamed:)` finds-or-creates the album via PhotoKit:
   `PHAssetChangeRequest` + `PHAssetCollectionChangeRequest`).
6. Photos **read/write** authorization is requested lazily at first save — full access
   is required because album management can't be done with add-only access. The asset
   still lands in the main library too; the album is an additional grouping, not a move.
   `Info.plist` therefore declares both `NSPhotoLibraryAddUsageDescription` and
   `NSPhotoLibraryUsageDescription`.

Coordinates: `watchRegion` / `feederRect` are normalized `CGRect`s (0…1). `FeederOverlay`
multiplies by the canvas size to draw, and clamps dragging so the box stays on-screen.

## Known rough edges / gotchas

- **Info.plist wiring.** The project sets `INFOPLIST_FILE = BirdFeederCam/Info.plist`
  with `GENERATE_INFOPLIST_FILE = YES`, so Xcode merges the generated keys into the
  hand-written `Info.plist` (which carries `NSCameraUsageDescription` and
  `NSPhotoLibraryAddUsageDescription`). If you add usage keys, edit that file.
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
