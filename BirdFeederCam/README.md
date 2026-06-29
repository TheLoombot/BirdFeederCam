# BirdFeederCam

A tiny SwiftUI + AVFoundation test app for an iPad bird feeder camera.

## What it does

- Shows a live rear-camera preview.
- Lets you drag a yellow box over the feeder.
- Watches only that region for motion.
- Saves a photo to the Photos app when enough motion is detected.
- Includes a Test Save button to verify Photos permissions.

## How to run

1. Open Xcode on your Mac.
2. Create a new iOS App project named `BirdFeederCam`.
3. Set the deployment target to iPadOS 17.0.
4. Delete the starter Swift files.
5. Drag the files in the `BirdFeederCam` folder into the project.
6. In `Info.plist`, add:
   - `NSCameraUsageDescription` = `Camera is used to watch the bird feeder.`
   - `NSPhotoLibraryAddUsageDescription` = `Photos are saved when bird feeder motion is detected.`
7. Build and run on the iPad.

## Suggested iPad settings

- Plug the iPad into power.
- Settings > Display & Brightness > Auto-Lock > Never.
- Turn brightness way down.
- Put the camera close to the glass to reduce reflections.

## Notes

This first version is deliberately simple. It uses pixel-difference motion detection, not bird recognition yet. A later version can add Vision/Core ML after motion is detected.
