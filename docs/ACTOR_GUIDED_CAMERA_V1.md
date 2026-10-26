# HOTICE guided Actor camera — implementation and QA contract

## 26 October 2026 — V1.1 implementation update (feature branch PR #17)

- **Name first:** Actors Studio no longer presents a Quick Actor / manual new-Actor save path. Enter Actor name and optional appearance notes, then explicitly continue to the permission-gated guided camera; the keyboard is dismissed before navigation.
- **Seven guided reference views:** front, left 25–35°, right 25–35°, left 40–60°, right 40–60°, chin up and chin down. The last four pose types are new and their pitch/yaw sign must be verified on physical Android/iOS hardware.
- **Review before save:** After all seven real photos pass capture-time pose checks, HOTICE shows thumbnails with a **Retake** action for each angle. An Actor is added only after explicit **Save Actor with 7 views** confirmation. Cancellation removes incomplete temporary photos.
- **Model adapter:** Seven positions are now named accurately (front, left, right, left-profile, right-profile, chin-up, chin-down) for later image-slot planning.
- **Automated checks:** new Flutter tests cover seven-angle pose boundaries and that the Actor-creation page has only the guided-camera path (no direct `Save actor`). Automated camera hardware, retake fidelity and biometric accuracy remain untested.
- **Photo QA advisory now implemented:** on-device sampled luminance, contrast and edge-detail heuristics flag overly dark, overexposed or low-detail photos in the seven-angle review, while allowing the user to Retake manually. Original images are never modified. These lightweight heuristics are **not calibrated focus/blur or biometric quality measurements**.
- **Known unsupported items:** Optional beauty/touch-up, encrypted persistent Actor vault, real 3D reconstruction, import/export, calibrated optical focus/exposure checks and real-provider connection still remain **planned**, not delivered.
- **Important safety:** Never claim this photo-capture system produces a perfect 3D model. Do not export/retain identity photos until explicit informed consent, durable encryption and deletion/export policies are in place.



**26 October 2026 — code implementation under review, NOT production sign-off.**

## What this feature really does
- Opens the device **front camera** on Android/iOS only after a clear on-screen consent action.
- Uses Flutter camera preview and **native Google ML Kit Face Detection** on image frames, with analysis throttling and a one-face policy.
- Guides the user through **seven requested angles** (front, left/right slight + profile, chin up/down) and estimates framing, face size, position and head yaw/roll.
- Turns red/green after four consecutive acceptable analysed frames, giving system click audio and haptic cues.
- **User presses Capture** on green. The captured still image is rechecked for exactly one detectable face and expected yaw before advancing. Retakes remain available.
- After seven images are captured and the review is explicitly confirmed, creates a named Actor profile and shows seven temporary device-local photo thumbnails in Actors Studio. No upload.
- Discards incomplete photos when capture is cancelled; deletes Actor reference photos when Actor is deleted; clears stale capture folder at next app launch.

**This is camera-assisted 2D multi-angle photo capture, not depth mapping, 3D reconstruction, guaranteed actor identity matching, face recognition, liveness verification or an AI provider integration.**

## Source, licenses and compatibility
- `camera ^0.12.1`, maintained by Flutter team; BSD-3-Clause; Android supports API 24+. Its CameraX Android implementation supports NV21 input image streaming.
- `google_mlkit_face_detection ^0.15.1`, community-maintained MIT Flutter wrapper around Google's native ML Kit SDK. The wrapper is open source; do not describe the native SDK as wholly open source.
- `path_provider ^2.1.6` (BSD-3-Clause) for the app-private temporary capture folder.
- Flutter scaffold is generated dynamically in GitHub Actions; `tools/prepare_mobile_camera.py` configures Android CAMERA permission, minimum Android SDK 24, iOS camera usage description and iOS minimum deployment target 15.5. The script must be rerun after `flutter create`, including on physical-device builds.
- CameraX NV21 stream bytes can historically be mislabeled as YUV420. This implementation requires a single supported packed plane and reports an incompatible-format error instead of sending unsafe/corrupt frames. Confirm latest `camera_android_camerax` on each target device.

## Security/privacy
- Explicit consent is required before camera permission/preview access.
- Only the opted-in user's front camera is used; no background capture or network upload is implemented.
- Image files reside in an **OS app-private TEMPORARY folder**, not encrypted biometric storage. Do not promise encryption at rest or permanent local durability.
- Deleting an Actor removes its temporary photo files where possible, and next launch removes any abandoned temporary photos. The in-memory Actor model loses these paths after a process restart.
- Face detection is on-device via native ML Kit; media bytes are not transmitted to provider servers in this feature. Check native SDK privacy statements before production release.
- A production persistent Actor vault will require secure encrypted app storage, per-user access controls, informed explicit consent, retention/deletion policy, account logout purge, backup policy and backend authorization before any sync.

## Remaining release gates / known issues
- Camera hardware permission UI cannot be reliably exercised by headless Flutter widget tests. **Real Android device testing is required.**
- Orientation compensation and left/right yaw sign may differ for mirrored selfie cameras, device rotation, specific OEMs, and iOS; validate visually with a live person and adjust.
- Colour, click and vibration are guidance, not photographic focus/lighting guarantees; add focus/blur, exposure, occlusion and eye-open scoring later if supported and tested.
- No image encryption, permanent identity storage, face tracking across days, gallery export, image upload, 3D rig or vendor-specific face locking yet.
- No test proves that all hardware cameras support concurrent still capture and stream start/stop; test device compatibility matrix.
- Require consent, denial, no-camera, background/resume, cancellation, retake, delete, low light, multiple faces, rotated-device and no-storage-space manual cases before release.

## CI evidence
Record the exact final green GitHub Actions run/commit in PR #16 after it finishes. Flutter analysis/widget tests and Android compile/emulator smoke tests are necessary but **not equivalent** to manual face-camera QA.

**Implementation PR:** https://github.com/parmtech/HOTICE/pull/16 (stacked on PR #11)  
**Tracking issue:** https://github.com/parmtech/HOTICE/issues/13

## Phone test steps
1. Install the newest **PR #16 debug APK**, not a previous main-branch APK. Note build SHA.
2. Open Demo Studio → Actors → Guided camera; type a NEW Actor name → Start real guided camera.
3. Approve the explicit consent screen and Android camera permission.
4. Test zero, two and one faces; move too close, too far, to the edge, tilt the head and rotate the device; red hint must change appropriately.
5. Face front, then left, then right. When alignment stays green, the click/haptic fires; capture each. Verify that the captured still is re-validated and retakes are possible.
6. Confirm 3 on-device previews in Actor profile; delete Actor and check UI; restart app and confirm stale captures are cleared.
7. Test deny/revoke camera permission and app background/foreground recovery; send the precise first exception and device name if anything fails.
