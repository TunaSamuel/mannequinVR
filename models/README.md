# Character models

Drop `.glb` / `.gltf` characters here when running the project from source.

- **Editor / desktop:** this folder is scanned automatically (together with
  `user://models`).
- **On Meta Quest:** the app scans its own external files folder instead:
  `/storage/emulated/0/Android/data/com.example.vrcharacterposer/files/models`
  — push models there with `adb push`, or copy them over USB. That location
  needs no Android storage permission.
- Override the folder entirely with the `VR_POSER_MODELS` environment variable
  or `--models-dir=/path` on the command line.

Models should be exported as **GLB** with their skeleton and blend shapes
(morph targets) included. FBX is not loaded at runtime: convert it to GLB in
Blender (`File > Export > glTF 2.0`, format "glTF Binary") or with ufbx.

`models/*.glb` and `*.gltf` are git-ignored so user content never enters the
repository. This README is kept so the folder exists.
