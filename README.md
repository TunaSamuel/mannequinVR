# mannequinVR

Load rigged 3D characters and pose them in mixed reality on **Meta Quest 3**.
Built with **Godot 4.6** and OpenXR.

Launch into passthrough, pick a character, move / rotate / scale it, pose joints
with grip, tweak blend shapes and mesh visibility, save poses, and walk around
the scene with the sticks.

## Features

| Area | Notes |
| --- | --- |
| OpenXR + alpha-blend passthrough | Transparent viewport, ambient/key lighting |
| Controllers and hand tracking | Shared grab / pointer path |
| Laser pointer with hit cursor | Controllers and hands |
| Runtime `.glb` / `.gltf` load | Validation warnings, recent models |
| Whole-character grab | Move, rotate, two-handed uniform scale |
| Floor height + Scale sliders | Models tab; optional floor ring (off by default) |
| Bone handles (FK) | Hover name labels, Major/All/Off filter, lock |
| Mirror L/R pose | Poses tab |
| Blend shapes | Paged sliders |
| Mesh part hide/show | Parts tab (Blender object / mesh names) |
| Pose save / load | Versioned JSON under `user://poses` |
| World-space panel | Auto-faces camera; drag header to move |
| Locomotion | Left stick walk, right stick turn |
| Help tab | Controls summary + handle size / face cam / ring |
| Headless self-test | 89 checks |

Not in scope for this build: full IK, animation playback, environments, props,
multi-character sessions, or desktop posing mode.

## Requirements

- Godot **4.6.x**
- Meta Quest 3 (OpenXR). Touch controllers and/or hand tracking
- For APK export: Godot Android export templates, Android SDK, JDK 17
- Optional: PC OpenXR runtime to test from the editor

## Running

```bash
godot --path . --editor
```

Main scene: `scenes/main.tscn`. Without an OpenXR runtime the app still starts
and shows a diagnostic screen listing model folders — that is not a desktop
posing mode.

## Getting characters onto the headset

**Bundle with the build** — put `.glb` files in the project’s `models/` folder
before export (the preset includes `models/*` in the PCK).

**Or push into the app’s external files directory** (no extra storage permission):

```bash
adb push my_character.glb /sdcard/Android/data/com.example.vrcharacterposer/files/models/
```

Scan order: `VR_POSER_MODELS` / `--models-dir=`, `user://models`, bundled
`res://models`, then (on Android) the external app folder above. The Models tab
lists each path and whether it exists when nothing is found.

Models must be **skinned glTF** (GLB preferred) with a skeleton; morph targets
become blend shapes. Export from Blender as **glTF 2.0 Binary**. Separate mesh
objects show up under the Parts tab for hide/show.

## Controls

| Action | Touch controller | Hand tracking |
| --- | --- | --- |
| Aim | Laser from OpenXR **aim** pose | Laser from index fingertip |
| UI (menus, sliders, buttons) | **Trigger** | Pinch |
| Pose bones / grab body | **Grip** | Pinch |
| Walk | Left stick | — |
| Turn | Right stick (X only) | — |
| Move / rotate character | Grip on body | Pinch on body |
| Uniform scale | Two grips, pull apart | Two pinches, pull apart |
| Pose a joint | Grip joint sphere, rotate wrist | Pinch joint, rotate hand |
| Panel | Trigger on controls; drag header to move | Pinch; same |

Aiming at a joint shows its **bone name**. Locked joints are dimmed and not
grabbable until unlocked.

### Panel tabs

- **Models** — load character, Floor height, Scale, Fit to 1.6 m, rescan
- **Shapes** — blend shape sliders (paged), reset all
- **Parts** — toggle mesh visibility, show/hide all
- **Poses** — reset pose, handle filter, **Mirror L/R**, **Lock hovered**,
  **Unlock all**, save/load presets
- **Help** — control summary; handle size; panel face-camera; floor ring

## Project layout

```
project.godot                 XR + mobile renderer, alpha-blend passthrough
openxr_action_map.tres        OpenXR action map
export_presets.cfg            Meta Quest 3 Android preset
scenes/main.tscn              XR rig, character root, interaction, panel
scripts/app.gd                bring-up, locomotion, floor ring
scripts/xr/                   interactors, laser, grab dispatcher
scripts/character/            library, loader, character rig
scripts/posing/               skeleton poser, bone handles, blend shapes, poses
scripts/ui/                   panel, 3D buttons/sliders
tests/                        headless self-test
models/                       drop test models here (git-ignored)
```

Priorities for grabs: panel (~40) > bone handles (20) > character body (5).
Bone rotation is pure FK via `Skeleton3D.set_bone_global_pose`.

## Tests

```bash
godot --headless --path . --import
godot --headless --path . res://tests/selftest.tscn
```

The suite exits non-zero on failure and does not require external model assets.

## Android / Quest export

Preset: standard APK, XR mode OpenXR, `arm64-v8a`, min SDK 29, target SDK 34,
`models/` included in the PCK.

```bash
godot --headless --path . --export-debug "Meta Quest 3" build/vr_character_poser.apk
adb install -r build/vr_character_poser.apk
```

Change `package/unique_name` and sign with your own keystore before any store
submission. Core OpenXR is enough for this build; Godot OpenXR Vendors is
optional for Meta-specific extras later.

## Known limitations

- Model load is synchronous on the main thread — large files can hitch.
- Folder scan is one level deep; no thumbnails.
- Mirror L/R depends on common left/right bone naming; unusual rigs may pair poorly.
- Zero-length bone rests can stack handles; use the Major filter or hide handles.
- Passthrough look, laser brightness, and pinch thresholds still benefit from
  more on-device tuning.

## AI assistance

This project was developed with substantial assistance from AI coding agents:
**Grok** (xAI) and **DeepSeek**. Human direction, device testing, and final
accept/reject of changes remain the project author’s responsibility.

## References

- [Godot XR / OpenXR documentation](https://docs.godotengine.org/en/stable/tutorials/xr/index.html)
- [GLTFDocument runtime loading](https://docs.godotengine.org/en/stable/classes/class_gltfdocument.html)
- Khronos glTF Sample Assets (validation only, not redistributed)
