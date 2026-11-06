# VR Character Poser

Load rigged 3D characters and pose them with your hands in mixed reality on
Meta Quest 3. Built with **Godot 4.6** and OpenXR, following
`VR_Character_Poser_Design_Document.md` and `VR_Character_Poser_Roadmap.md`.

The MVP core loop is implemented: launch into passthrough, pick a character,
move/rotate/scale it, pose joints directly, tweak blend shapes, save the pose.

> **Device status:** all logic below is verified by a headless test suite and by
> loading real glTF samples, but the build has **not yet been run on a Quest 3**.
> Passthrough appearance, pinch thresholds and frame rate still need hardware
> validation.

## Implemented

| Area | State |
| --- | --- |
| OpenXR bring-up, alpha-blend passthrough, transparent viewport | done |
| Controllers + hand tracking behind one grab interface | done |
| Runtime `.glb` / `.gltf` loading with validation and warnings | done |
| Whole-character move / rotate / two-handed uniform scale | done |
| Bone handles, FK drag rotation, bone filter, reset pose | done |
| Blend shape enumeration + sliders | done |
| Versioned JSON pose presets (bones + shapes + character transform) | done |
| World-space touch panel (models / shapes / poses) | done |
| Headless self-test (54 checks) | done |
| Bone locking UI, IK, animation, environments, props, desktop mode | not started (out of MVP scope) |

## Requirements

- Godot **4.6.x** (developed and verified with 4.6.3).
- Meta Quest 3 (OpenXR runtime). Touch controllers and/or hand tracking.
- For APK export: Android build template, Android SDK, JDK 17.
- Optional: a PC OpenXR runtime plus headset to test VR from the editor.

## Running

```bash
godot --path . --editor      # open the project, then press Play
```

The main scene is `scenes/main.tscn`. Without an OpenXR runtime the app starts
normally, prints diagnostics and shows a one-page notice listing the model
folders — that screen is a developer aid, not a desktop posing mode.

## Getting characters onto the headset

The app reads models from its own external files directory, which needs no
storage permission and is reachable over USB/MTP or adb:

```
/storage/emulated/0/Android/data/com.example.vrcharacterposer/files/models
```

```bash
adb push my_character.glb /sdcard/Android/data/com.example.vrcharacterposer/files/models/
```

When running from source, `models/` in the project and `user://models` are
scanned. `VR_POSER_MODELS=/some/folder` or `--models-dir=/some/folder`
overrides the search path.

Models must be **skinned glTF**: GLB preferred, skeleton included, morph targets
exported to become blend shapes. FBX is rejected at runtime with conversion
advice — export GLB from Blender (`File > Export > glTF 2.0`, "glTF Binary").

## Controls

| Action | Touch controller | Hand tracking |
| --- | --- | --- |
| Grab / press | Grip (analog, hysteresis) | Pinch (thumb + index tip distance) |
| Move / rotate character | Grip anywhere on the body | Pinch the body |
| Uniform scale | Grip with both hands, pull apart | Pinch with both hands, pull apart |
| Pose a joint | Grip a joint handle, rotate your wrist | Pinch a handle, rotate your hand |
| Panel | Touch buttons and sliders; drag the top bar to move the panel | Same |

Bone handles are drawn on top of the mesh (X-ray) so joints inside a body stay
reachable, and they follow their joint every frame. Bone handles take priority
over the character body when both are in reach.

### Panel

- **Models** — scans the model folders; press a name to load, `<`/`>` page,
  "Rescan models" refreshes, the loaded model stays highlighted.
- **Shapes** — one slider per blend shape (paged), "Reset all".
- **Poses** — "Reset pose", cycle handle filter (`All` / `Major` / `Off`),
  "Save pose", and load any saved preset.

Pose presets are JSON files in `user://poses` (format version `1`): character
transform, bone local poses per skeleton, and blend shape weights. Bones and
shapes are matched by name, so presets survive re-export of the same character.

## Project layout

```
project.godot                 XR + renderer settings (mobile renderer, alpha-blend passthrough)
openxr_action_map.tres        generated from Godot's built-in OpenXR action sets
export_presets.cfg            "Meta Quest 3" Android preset (Gradle, OpenXR, arm64)
scenes/main.tscn              XR rig, character root, interaction manager, panel
scripts/app.gd                bring-up, passthrough, wiring, diagnostics
scripts/xr/                   interactor base, controller, hand (pinch), grab dispatcher
scripts/character/            model library, glTF loader/analyser, character rig + grabs
scripts/posing/               skeleton poser, bone handles, blend shapes, pose store
scripts/ui/                   in-world panel, 3D buttons/sliders, style
tests/selftest.tscn|.gd       headless test suite
tools/generate_action_map.gd  regenerates openxr_action_map.tres
models/                       drop test models here (git-ignored)
```

### Interaction model

Every grab source (controller or hand) exposes the same four things: grab point,
grab orientation, grip strength, tracking state. `InteractionManager` routes a
grip to the highest-priority target under that point. Targets are registered in
the `grab_target` group and implement `can_grab`, `begin_grab`, `drag_grab`,
`end_grab`; priorities are panel (40) > bone handles (20) > character (5).

Bone rotation applies the hand's rotation delta, converted into skeleton space,
to the bone's global pose with `Skeleton3D.set_bone_global_pose`, so children
follow and no IK is involved.

## Tests

```bash
godot --headless --path . --import     # first run (builds the script class cache)
godot --headless --path . res://tests/selftest.tscn
```

The suite exits non-zero on failure and covers: runtime glTF round-trip and
error paths, model analysis/warnings, skeleton normalisation, FK bone rotation
with child propagation, reset pose, blend shape weights, pose save/load and
library listing, model folder scanning/recents, grab routing and release,
two-handed scaling/translation, and panel construction for every tab plus
dragging the panel. It builds its own character with blend shapes, so no
external assets are required.

In addition, real models were checked during development: Khronos
**CesiumMan** (skinned, 19 bones, 4.7k tris — skin binding intact, child joints
follow parent posing) and **AnimatedMorphCube** (2 morph targets, no skeleton ->
correct warning).

## Android / Quest export

The included preset uses a Gradle build (required for OpenXR), XR mode
`OpenXR`, `arm64-v8a`, min SDK 29, target SDK 34.

1. Install export templates and the Android build template
   (`Editor > Manage Export Templates`), and set the Android SDK path in
   `Editor Settings > Export > Android`.
2. Export:
   ```bash
   godot --headless --path . --export-debug "Meta Quest 3" build/vr_character_poser.apk
   adb install -r build/vr_character_poser.apk
   ```
3. Change `package/unique_name` and sign with your own keystore before any store
   submission.

Passthrough comes from `xr/openxr/environment_blend_mode = 2` (alpha blend) plus
a transparent viewport; the engine default OpenXR action map covers hand
tracking and the Oculus Touch profile. Meta's Touch Plus controllers bind
through Meta's OpenTouch compatibility profile. The **Godot OpenXR Vendors**
plugin is not required for this MVP and can be added later for Meta-specific
extras.

## Known limitations / next steps

- **Hardware validation is outstanding**: passthrough tint, hand-tracking pinch
  thresholds (currently fingertips < 2.2 cm closed, > 5.8 cm open), handle
  reachability and Quest frame rate all need a device pass.
- Model loading is synchronous on the main thread — large files can hitch.
- Folder scanning is one level deep and has no thumbnails or validation on
  import beyond loader warnings.
- Bone locking exists only as a filter (All/Major/Off); per-bone locks are a
  natural next step, as are mirror-pose and a built-in pose library.
- If a model imports with zero-length bone rest offsets, handles overlap; that
  is a content problem and is only mitigated by the handle filters.
- No IK, animation playback, environments, props or multiple characters — these
  are deliberately deferred by the design document.

## References

- Godot XR / OpenXR documentation and action map editor
- `GLTFDocument` runtime loading
- Khronos glTF Sample Assets (used for validation only, not redistributed)
