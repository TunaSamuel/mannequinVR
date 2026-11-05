# VR Character Poser — Development Roadmap

**Target Engine:** Godot 4.6+  
**Primary Platform:** Meta Quest 3 Standalone  
**Last Updated:** Initial planning  

## Guiding Principles
- Ship a usable MVP as early as possible.
- Prefer reliability and clear interaction over feature density.
- Keep the codebase modular so deferred features can be added cleanly.
- Validate every major system on actual Quest 3 hardware early.

---

## Phase 0 — Project Foundation (1–2 weeks)
**Goal:** Working XR project that boots on Quest 3 with passthrough and basic hand/controller tracking.

- Create Godot 4.6 project.
- Enable OpenXR, configure Android export preset for Meta Quest (Quest 3 support, hand tracking).
- Install / configure Godot OpenXR Vendors plugin.
- Enable Meta passthrough (Project Settings → XR → OpenXR → Advanced → Meta Passthrough).
- Set up transparent background + correct environment blend mode.
- Basic XROrigin3D + camera + left/right controllers + hand trackers.
- Confirm controllers and hand tracking both report poses correctly.
- Simple debug visualization (hand joints or controller models).

**Exit Criteria:** APK installs and runs on Quest 3; user sees real environment; both input methods track.

---

## Phase 1 — Model Loading & Basic Transform (2–3 weeks)
**Goal:** Load a character and move / rotate / scale it as a whole.

- Implement folder scanning for `.glb` / `.gltf` (and later FBX where feasible).
- Runtime loading via `GLTFDocument` / `GLTFState`.
- Parent loaded model under a controllable `CharacterRoot` Node3D.
- Grab interaction on the character root (or a large bounding handle) using both controllers and hand tracking.
- Free translation, rotation, and scale (start with uniform scale; add non-uniform later if needed).
- Basic model browser UI (list of files, load / unload).
- Error handling for missing skeleton, missing materials, oversized models.

**Exit Criteria:** User can select a model from a folder, load it, and freely position / rotate / scale it in passthrough space.

**Suggestions / Ideas:**
- Add a simple “floor snap” or gravity-assist option so the character rests on a virtual ground plane.
- Show a lightweight bounding box or silhouette while loading.
- Cache recently used models for faster re-load.

---

## Phase 2 — Bone Posing System (3–4 weeks)
**Goal:** Mannequin-style bone manipulation by gripping and rotating individual bones.

- Locate `Skeleton3D` after load.
- Generate interactive handles (spheres, short axis gizmos, or bone capsules) at selected bones.
- Configurable bone filter (all bones, major bones only, user-defined list).
- Grip + drag to rotate bone relative to parent (pure FK).
- Optional limited translation for bones that support it.
- Visual feedback (highlight on hover / grip, axis constraints).
- Bone lock / unlock and hierarchical lock.
- “Reset to rest pose” and “Reset selected bone” actions.
- Save / load pose presets (JSON or Godot resource containing bone rotations).

**Exit Criteria:** User can grip any major bone and pose the character into stable mannequin poses; poses can be saved and restored.

**Suggestions / Ideas:**
- Two-handed posing: one hand holds the parent bone, the other rotates the child for more control.
- Quick “mirror pose” for left/right symmetry.
- Bone name labels that appear only when looking at or hovering a handle (reduces visual clutter).
- Simple angle constraints (e.g., knee cannot bend backward beyond a limit) as optional safety.
- “Pose library” of common starting poses (T-pose, A-pose, sitting, etc.).

---

## Phase 3 — Blend Shape Manipulation (1–2 weeks)
**Goal:** Control morph targets on the loaded character.

- Enumerate all blend shapes / morph targets from MeshInstance3D nodes.
- World-space or wrist-attached UI panel with sliders (or value fields).
- Real-time update of morph weights.
- Grouping or search if a model has many shapes.
- Optional “reset all blend shapes” button.
- Persist blend-shape weights together with bone poses in presets.

**Exit Criteria:** User can open a panel and adjust any available blend shape while the character remains posed.

**Suggestions / Ideas:**
- Gesture shortcuts (e.g., pinch near the face to open facial blend-shape panel).
- “Favorite” shapes that appear in a compact radial menu.
- Visual preview of the shape name near the affected region when adjusting.

---

## Phase 4 — Polish, Stability & Usability (2–3 weeks)
**Goal:** Make the MVP feel solid and shippable.

- Unified input handling refinements (consistent grab feel between controllers and hands).
- Performance profiling on Quest 3 (draw calls, bone count, blend-shape cost).
- Model validation warnings (high poly, missing skeleton, no blend shapes, etc.).
- Basic onboarding / tooltips / help panel.
- Settings: handedness, handle size, show/hide bone labels, passthrough intensity if available.
- Robust unload / reload of models without leaks.
- Save system reliability and folder management.
- Crash reporting / logging for field testing.

**Exit Criteria:** Reliable daily-driver experience for posing characters on Quest 3; ready for limited external testing.

---

## Phase 5 — Optional Enhancements (Post-MVP)
These items are explicitly out of scope for the first versions but are natural next steps.

### Near-Term Candidates
- Simple FK/IK hybrid: allow dragging an end effector (hand, foot) and solve a short chain.
- Basic jiggle / secondary motion on selected bones (optional toggle).
- Pose export (JSON, or glTF with posed skeleton).
- Improved FBX runtime path or automatic conversion helper.
- Multiple characters in the same session.
- Simple prop spawning (load additional `.glb` objects and place them).

### Medium-Term
- Selectable 3D environments (load environment `.glb`, place character inside).
- Scale character relative to environment.
- Look-at / simple animation playback on top of posed base.
- Desktop / non-VR mode (mouse + keyboard + gizmo controls) for the same posing tools.
- Higher-quality rendering path for desktop (including future ray-tracing if Godot support matures).

### Longer-Term Ideas
- Cloud or local pose sharing.
- Recording short pose sequences.
- Integration with external animation tools or export pipelines.
- Accessibility options (voice commands, larger handles, reduced motion).

---

## Suggested Technical Priorities & Best Practices
1. **Test on device continuously** — Passthrough, hand tracking, and performance only reveal issues on Quest 3 hardware.
2. **Prefer GLB/GLTF** — Document a clear conversion workflow for FBX users (Blender is the practical recommendation).
3. **Keep interaction code modular** — Separate “grab target”, “bone handle”, and “character root” so later IK or physics can plug in.
4. **Start with major bones only** — Full skeleton handles can become visually and computationally noisy; expand later.
5. **Action map first** — Define clear OpenXR actions early so controller and hand inputs stay consistent.
6. **Version the pose format** — Even a simple JSON schema should include a version field for future compatibility.

---

## Success Metrics for MVP
- User can go from empty scene → loaded custom character → fully posed (bones + blend shapes) in under two minutes.
- Both controllers and hand tracking feel usable for the core tasks.
- Application remains stable for 30+ minute posing sessions.
- Models from common sources (Blender exports, VRM converted to GLB, etc.) load without requiring special preparation beyond standard export settings.

---

## Appendix — Recommended Starting Resources
- Godot 4.6 XR documentation and OpenXR setup guides.
- Godot OpenXR Vendors plugin (Meta passthrough & features).
- Godot XR Tools (optional foundation for grab interactions; extend rather than rely on exclusively).
- Official OpenXR hand tracking demo projects.
- GLTFDocument runtime loading examples.

This roadmap is intentionally sequenced so that each phase produces a testable, demonstrable improvement. Adjust timelines based on available development resources and the complexity of the specific character models being targeted.
