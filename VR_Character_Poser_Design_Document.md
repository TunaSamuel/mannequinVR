# VR Character Poser — Design Document

**Version:** 1.0 (Initial Design)  
**Target Platform:** Meta Quest 3 (standalone)  
**Engine:** Godot 4.6+  
**Document Status:** Foundation for implementation and future iteration  

## 1. Overview

VR Character Poser is a standalone Meta Quest 3 application that allows users to load custom 3D character models and pose them interactively in mixed reality (passthrough). The core focus is on direct manipulation of the character’s transform, individual bones, and blend shapes (morph targets) using both controllers and hand tracking.

The application prioritizes simplicity, reliability, and immediate usability for the first release. Advanced features such as physics, inverse kinematics, environments, and desktop mode are deferred.

## 2. Goals and Non-Goals

### 2.1 Primary Goals (MVP)
- Load character models from a user-accessible folder (primarily `.glb` / `.gltf`; FBX support where practical).
- Free transform of the loaded character (position, rotation, uniform/non-uniform scale).
- Interactive bone posing via grip + move / rotate, producing mannequin-style poses.
- Blend-shape (morph target) manipulation via UI or direct controls.
- Full support for Meta Quest 3 controllers **and** hand tracking.
- Continuous passthrough so the user remains grounded in the real environment.
- Stable standalone Android APK export for Quest 3.

### 2.2 Explicit Non-Goals for First Versions
- Jiggle / soft-body physics.
- Animation playback or look-at systems.
- Custom 3D environments or scene loading.
- Spawnable props or additional interactive objects.
- Selectable player avatars.
- Full FK/IK solvers (basic bone rotation is sufficient; IK may be added later).
- Desktop / non-VR mode.
- Ray tracing or high-end desktop rendering features.

## 3. Technical Architecture

### 3.1 Engine and XR Stack
- **Engine:** Godot 4.6 or later (native OpenXR 1.1 support, improved Android XR tooling, frame synthesis options).
- **XR Interface:** OpenXR (core).
- **Vendor Extensions:** Godot OpenXR Vendors plugin (recommended for Meta-specific features including robust passthrough and hand-tracking configuration).
- **Renderer:** Compatibility or Mobile renderer (validated for Quest 3 standalone performance).
- **Input:** Unified handling of controllers (`XRController3D`) and hand trackers (`/user/hand_tracker/left` and `/user/hand_tracker/right`) via Godot’s XR action map and skeleton modifiers.
- **Passthrough:** Enabled via Project Settings → XR → OpenXR → Meta → Passthrough (Advanced Settings). Viewport transparent background + environment blend mode set appropriately.

### 3.2 Model Loading Pipeline
1. User places models in a designated folder (e.g., `/Android/data/<package>/files/Models` or a user-selected directory via Android storage access if permissions allow).
2. Application scans for supported files.
3. Runtime loading:
   - Preferred: `GLTFDocument` + `GLTFState` for `.glb` / `.gltf`. This path reliably preserves skeletons, blend shapes, materials, and hierarchy.
   - FBX: Primary recommendation is offline conversion to GLB (via Blender, ufbx, or similar). Runtime FBX support is secondary and may be limited to models already imported in the editor or converted on device if a lightweight converter is later integrated.
4. After load, the root node is parented under a controllable `CharacterRoot` (Node3D) that owns the global transform. The `Skeleton3D` (if present) is located and prepared for interaction. Blend shapes are enumerated from all `MeshInstance3D` nodes that contain them.

### 3.3 Interaction Model
- **Character Transform:** Grab the character root (or a dedicated handle) with either hand/controller to translate, rotate, and scale. Scale can be uniform or per-axis depending on gesture (e.g., two-handed scale).
- **Bone Posing:**
  - Visual bone indicators (simple spheres or axis gizmo handles) are generated at each relevant bone position (or a user-selectable subset of major bones).
  - Grip + move on a bone indicator applies rotation (and optionally limited translation) relative to the parent bone, producing direct FK-style mannequin posing.
  - Bones can be locked individually or as hierarchies.
  - A “reset pose” action restores the original rest pose or a saved pose.
- **Blend Shapes:**
  - A floating or wrist-attached UI panel lists available morph targets with sliders (0–1 or custom range).
  - Optional quick-access radial menu or gesture for frequently used shapes.
- **Input Parity:** Every interaction must work with both controllers (grip, trigger, thumbstick) and hand tracking (pinch, grab pose, open hand). Godot XR Tools or custom grab logic can be used as a foundation; bone handles will require custom or extended grab targets.

### 3.4 Scene Structure (High-Level)
```
XROrigin3D
├── XRCamera3D
├── LeftController / LeftHand
├── RightController / RightHand
├── CharacterRoot (Node3D)          ← movable/scalable root
│   └── LoadedModel (scene root)
│       └── Skeleton3D + MeshInstances + BoneHandles
├── UI Layer (World-space or screen-space panels)
└── Passthrough / Environment (transparent)
```

### 3.5 Performance Considerations (Quest 3)
- Keep draw calls and bone count reasonable; many consumer character models are acceptable, but very high-poly + high-blend-shape models may need LODs or warnings.
- Prefer single-pass stereo or Godot’s XR rendering optimizations.
- Limit simultaneous interactive bone handles if necessary (e.g., show only major bones by default).
- Avoid heavy physics in MVP; pure transform manipulation is preferred for stability and performance.

## 4. User Experience Flow

1. **Launch** → Passthrough activates, empty scene or simple floor grid appears.
2. **Model Selection** → Browse folder / recent models → preview thumbnail or name → load.
3. **Posing Session**
   - Move / rotate / scale whole character.
   - Grab individual bone handles to rotate limbs, spine, head, etc.
   - Open blend-shape panel and adjust facial or body morphs.
   - Optional: save current pose as a preset (local storage).
4. **Session End** → Unload model, return to browser, or quit.

## 5. Data & Persistence
- Models remain external files (user-managed).
- Saved poses stored as simple JSON or Godot resource (bone rotations + blend-shape weights) in application storage.
- No cloud or account system in MVP.

## 6. Platform & Export Requirements
- Android export preset configured for Meta Quest (OpenXR mode, Quest 3 support, hand tracking enabled).
- Gradle build recommended.
- Minimum SDK / target SDK aligned with current Quest requirements.
- Permissions: storage access for model folder (scoped storage compliant).

## 7. Risk Areas & Mitigations
| Risk | Mitigation |
|------|------------|
| Runtime FBX loading complexity | Prioritize GLB/GLTF; document conversion workflow; treat FBX as secondary |
| Bone handle precision with hand tracking | Visual feedback, snap-to-axis options, controller fallback always available |
| High-poly / high-blend-shape performance | Model size warnings, optional bone culling, LODs later |
| Passthrough black screen / configuration | Follow current OpenXR + Meta extension settings carefully; test early |
| Skeleton hierarchy differences across models | Robust bone discovery; allow user to hide/show handles |

## 8. Extensibility Notes
The architecture deliberately keeps the character root, skeleton interaction layer, and UI modular so that later features (environments, props, simple IK, desktop mode) can be added without rewriting the core posing system.

---

*This document is intended as the authoritative starting specification for development and for hand-off to additional tools or collaborators.*
