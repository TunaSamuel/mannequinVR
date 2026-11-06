# VR Character Poser

Load rigged 3D characters and pose them with your hands in mixed reality on
Meta Quest 3. Built with **Godot 4.6** and OpenXR, following
`VR_Character_Poser_Design_Document.md` and `VR_Character_Poser_Roadmap.md`.

The MVP core loop is implemented: launch into passthrough, pick a character,
move/rotate/scale it, pose joints directly, tweak blend shapes, save the pose.

> **Device status:** the app has been built and run on a Quest 3 once. That pass
> found eight problems — all fixed (see [Fixes from the first headset
> pass](#fixes-from-the-first-headset-pass)) — but the fixes have **not been
> re-tested on hardware yet**. Passthrough appearance, laser visibility, pinch
> thresholds and frame rate still need a second device pass.

## Implemented

| Area | State |
| --- | --- |
| OpenXR bring-up, alpha-blend passthrough, transparent viewport, `use_xr` viewport | done |
| Controllers + hand tracking behind one grab interface | done |
| Laser pointer with hit cursor on controllers and hands | done (needs device pass) |
| Runtime `.glb` / `.gltf` loading with validation and warnings | done |
| Whole-character move / rotate / two-handed uniform scale | done |
| Panel scale controls + automatic fit of oversized imports | done |
| Bone handles, FK drag rotation, hover highlight, bone filter, reset pose | done |
| Blend shape enumeration + sliders | done |
| Versioned JSON pose presets (bones + shapes + character transform) | done |
| Ambient + shadowless key lighting for passthrough | done (needs device pass) |
| World-space touch panel (models / shapes / poses) | done |
| Headless self-test (89 checks) | done |
| Bone locking UI, IK, animation, environments, props, desktop mode | not started (out of MVP scope) |

## Requirements

- Godot **4.6.x** (developed and verified with 4.6.3).
- Meta Quest 3 (OpenXR runtime). Touch controllers and/or hand tracking.
- For APK export: Godot Android export templates, Android SDK, JDK 17.
- Optional: a PC OpenXR runtime plus headset to test VR from the editor.

## Running

```bash
godot --path . --editor      # open the project, then press Play
```

The main scene is `scenes/main.tscn`. Without an OpenXR runtime the app starts
normally, prints diagnostics and shows a one-page notice listing the model
folders — that screen is a developer aid, not a desktop posing mode.

## Getting characters onto the headset

There are two reliable routes. **Bundle the model with the build** — copy the
file into `models/` in the project, export, and it ships inside the APK (the
export preset's include filter keeps `models/*` in the PCK). Nothing needs
copying onto the headset, and this is what the first headset pass was missing.

Or **push it into the app's own external files directory**, which needs no
storage permission:

```
adb push my_character.glb /sdcard/Android/data/com.example.vrcharacterposer/files/models/
```

That directory is
`/storage/emulated/0/Android/data/com.example.vrcharacterposer/files/models`.
Android 11+ hides `Android/data` from the on-device Files app and many third
party file managers, so a file dragged around on the headset itself may land in
`Download/` and never be seen. `adb push` always works, and so does the
`models/` folder bundled into the export.

The app scans, in order: `VR_POSER_MODELS` or `--models-dir=`, `user://models`,
the bundled `res://models`, and (on Android) the external app folder above.
When the Models tab is empty it lists each of those paths with its status, which
makes "why is my model not there" answerable from inside the headset.

Models must be **skinned glTF**: GLB preferred, skeleton included, morph targets
exported to become blend shapes. FBX is rejected at runtime with conversion
advice — export GLB from Blender (`File > Export > glTF 2.0`, "glTF Binary").

## Controls

| Action | Touch controller | Hand tracking |
| --- | --- | --- |
| Aim | Laser from the controller's OpenXR **aim** pose | Laser from the index fingertip, along the pointing finger |
| Grab / press | Grip (analog, hysteresis) | Pinch (thumb + index tip distance) |
| Move / rotate character | Aim at the body and grip | Aim at the body and pinch |
| Uniform scale | Grip with both hands, pull apart | Pinch with both hands, pull apart |
| Pose a joint | Aim at a joint, grip, rotate your wrist | Aim at a joint, pinch, rotate your hand |
| Panel | Aim at the panel and grip; drag the top bar to move it | Aim and pinch; same |

Every controller and hand draws a **laser with a cursor dot**: cyan when the
ray hits nothing, amber when it is on something you can grab or press. The
pointer's hit point is the grab point, so joints and panel controls work at
arm's length, and the joint you aim at lights up before you touch it. When the
ray misses, grabs fall back to the old direct-touch position (the controller tip
or the pinch midpoint), so pinching a joint right in front of you still works.

Bone handles are drawn on top of the mesh (X-ray) so joints inside a body stay
reachable, and they follow their joint every frame. Bone handles take priority
over the character body when both are in reach.

### Panel

- **Models** — scans the model folders; press a name to load, `<`/`>` page,
  "Rescan models" refreshes, the loaded model stays highlighted. `Scale -` /
  `Scale +` change the character size (20%–300%) and `Fit to 1.6 m` rescales to a
  human height. When nothing is found the tab lists every folder it searched and
  whether it exists, so a missing model is diagnosable on the headset itself.
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
export_presets.cfg            "Meta Quest 3" Android preset (OpenXR, arm64, models/ included)
scenes/main.tscn              XR rig, character root, interaction manager, panel
scripts/app.gd                bring-up, passthrough, wiring, diagnostics
scripts/xr/                   interactor base, controller, hand (pinch), laser pointer, grab dispatcher
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

The suite exits non-zero on failure (89 checks) and covers: runtime glTF
round-trip and error paths, model analysis/warnings, skeleton normalisation, FK
bone rotation with child propagation, reset pose, blend shape weights, pose
save/load and library listing, model folder scanning/recents/diagnostics, grab
routing and release, grabs that outlive their freed target, laser hit tests
(button rectangle, joint sphere, character box) and joint hover highlighting,
character scale controls and auto-fit, two-handed scaling/translation, and panel
construction for every tab plus dragging the panel. It also instantiates
`scenes/main.tscn` to check the lighting, aim-pose wiring and pointer setup. It
builds its own character with blend shapes, so no external assets are required.

In addition, real models were checked during development: Khronos
**CesiumMan** (skinned, 19 bones, 4.7k tris — skin binding intact, child joints
follow parent posing) and **AnimatedMorphCube** (2 morph targets, no skeleton ->
correct warning).

## Android / Quest export

The included preset uses a standard APK export (no Gradle build template
needed, since the project ships no Android plugins), XR mode `OpenXR`,
`arm64-v8a`, min SDK 29, target SDK 34, and includes `models/` in the PCK. Turn
`gradle_build/use_gradle_build` back on if you later add native plugins such as
Godot OpenXR Vendors.

1. Install export templates (`Editor > Manage Export Templates`) and set the
   Android SDK path in `Editor Settings > Export > Android`.
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

## Fixes from the first headset pass

Issues reported after the first Quest 3 build, and what changed:

| Reported | Resolution |
| --- | --- |
| `Trying to assign invalid previously freed instance` in `interaction_manager.gd` | Loading a character frees every joint handle; the manager now drops a grab when its target leaves the tree and never assigns a freed node, so the per-frame error is gone (covered by the "freed grab targets" test). |
| No hands, no cursor, unclear what was grabbable | Every controller and hand now draws a laser with a hit cursor, and grab targets highlight on hover. Controllers are bound to the OpenXR **aim** pose, so the ray goes where you point. |
| `OpenXR: No viewport was marked with use_xr` | `app.gd` marks the root viewport with `use_xr` and makes the XR camera current when a session is live, instead of a local hack. |
| Model far too large, no way to shrink it | The Models tab gained `Scale -` / `Scale +` and `Fit to 1.6 m`; on load the fit is measured from the instantiated meshes (not import stats) and characters outside 0.55–2.0 m are rescaled automatically. |
| Shapes tab loaded some shapes, then froze | Panel rebuilds are no longer re-entrant: loading a model frees the very button that emitted `pressed`, and the nested rebuild that followed is what could hang. Rebuild requests are now collapsed. |
| Scene was too dark to see the model | Added a `WorldEnvironment` with ambient light plus a shadowless key light and fill light, so a character is lit even with a transparent passthrough background. |
| XR shaders were not enabled by default | `xr/shaders/enabled=true` in `project.godot` (asserted by the test suite). |
| Six `Unicode parsing error ... Unexpected NUL character` lines | Not project content: the files Godot complains about are its own cache, `.godot/uid_cache.bin`. Deleting that file (or `.godot/`) clears it; the tracked `.gd` files contain no NUL bytes. |
| Models were not detected in the exported build | The preset now bundles `models/` into the APK, the package name is read from the app's data directory instead of `/proc`, and the panel lists every searched folder with its status. |

Godot OpenXR Vendors and XR Tools are still not dependencies: the project only
uses core OpenXR (hand tracking, action map, alpha blend). Adding them is only
needed for Meta-specific extras.

## Known limitations / next steps

- **Hardware re-validation is outstanding**: the fixes above are covered by
  headless tests only. Passthrough tint, laser brightness, hand-tracking pinch
  thresholds (currently fingertips < 2.2 cm closed, > 5.8 cm open), handle
  reachability and Quest frame rate all need a second device pass.
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
