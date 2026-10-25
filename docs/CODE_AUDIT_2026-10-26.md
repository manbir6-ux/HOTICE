# HOTICE Code Audit — 26 October 2026

**Scope:** Flutter Android/iOS UI prototype code under `lib/`, unit/widget tests, Android integration test and GitHub Actions. Reviewed layout, navigation, store logic, character identity presets, storyboard, credits demo, and crash diagnostics.

## Verified root cause from real device

The user's v0.2.0 diagnostic screenshot identified the FIRST exception as:

```
BoxConstraints has a negative minimum width.
BoxConstraints(w=-50.0, 0.0<=h<=Infinity; NOT NORMALIZED)
```

`lib/src/welcome.dart` previously used `constraints.maxWidth - 50` in two `SizedBox(width: ...)` values. A zero-width transient Android frame produced exactly -50. This is a code-level match to the reported first exception, not just speculation. The subsequent `_dependents.isEmpty` error is downstream of the widget mounting failure.

**Fix:** clamp responsive sizing, skip rendering for transient near-zero layouts and provide a compact, illustrated layout for narrow phones. A dedicated widget test cycles 0, 1, 25, 49, 50, 51, 120, 240, 320, 393, 820 and 1000 logical pixel widths without invalid constraints.

## Additional risks addressed

| Severity | Finding | Change |
| --- | --- | --- |
| High | Responsive welcome action Row overflow at narrow widths | Separate mobile hero and scaled actions |
| High | Projects grid used an `InkWell` outside the styled `Material` card | Move the tap handler inside `StudioPanel`'s Material surface and clamp width |
| Medium | Extremely narrow informational notice and primary CTA can overflow | Adaptive notice layout and scaled primary button |
| Medium | Normal Video and Music Video Studio modes destroyed unsaved text when toggled | Keep both editors mounted with `IndexedStack` |
| Medium | Saved music storyboards were listed but could not be reopened | Tap to load a copied snapshot and edit it |
| Medium | Standalone storyboard editor did not refresh after saving without a parent listener | Local refresh after successful save |
| Medium | Multiple historical APKs all identified themselves as v0.1.0+1 | Distinct v0.2.0 Android artifact names, run-specific build numbers, and on-screen SHA/build ID |
| High | Secondary Flutter framework failure obscured first exception | First-error recorder and copyable debug diagnostics |
| Medium | UI tests did not represent Android navigation | GitHub Actions Android emulator navigation smoke test plus edge-width widget tests |

## Source modules inspected

- `main.dart`: application lifecycle, Navigator, tabs, More, account switching, themes
- `welcome.dart`: responsive welcome and demo email UX
- `design.dart`: Material cards, shared buttons, previews and notice layouts
- `projects_generation.dart`: project grid, creation dialogs, model-specific format controls and draft previews
- `generation_hub.dart`: Normal/Music mode switching and text preservation
- `music_studio.dart`: storyboard templates, edit/move/save/reopen, no real audio or model processing
- `avatar_studio.dart`, `avatar_identity.dart`: character presets, local prompt guidance and five-angle planning-only guide
- `account_credits.dart`: demo profiles, themes and illustrative checkout
- `state.dart`: memory-only workspaces, project ownership checks, avatar name validation and demo draft rules
- `video_models.dart`: mock capability matrix, duration/aspect/attachment constraints, unverified quote exclusion
- `dialogs.dart`: field validation, dialog-owned TextEditingController
- `diagnostics.dart`: first Flutter error capture and build ID
- `tools/brand_android.py`: reproducible temporary launcher icon generation
- `.github/workflows/flutter_ci.yml`: analyze/tests, identifiable debug APK, real emulator test

## Not implemented and not to be misrepresented

The existing product is explicitly a demo UI. Server authentication, storage persistence, real video AI APIs, official provider capability/pricing discovery, Stripe/PayPal, audio/lyrics sync, camera/3D scanning, biometric matching, real media exports and production identity/security controls **are not connected**.

This audit is a source review and automated QA effort, not a claim of fully exhaustive testing or security certification. Static analysis passing does not guarantee a physical-phone experience. A real-device test is needed before closing [Issue #9](https://github.com/parmtech/HOTICE/issues/9).

## Release checks

1. Latest branch SHA must pass Flutter analyze and **all** tests under `test/`.
2. Android emulator journey must pass.
3. A versioned APK must be built and published as a GitHub Actions artifact for **that exact SHA**.
4. User installs that build after verifying the build ID.
5. On the affected real Android phone, repeat launch → guest demo → New Project → normal/music mode → avatars → credits → settings/accounts, plus rotation/large text.
6. Close Issue #9 only after no repeat crash; if it recurs, capture the diagnostic **first exception** and stack, not only `_dependents.isEmpty`.

No live billing or secrets should be added to this testing milestone.
