class_name SkeletonPoser
extends Node3D
## Generates and maintains the interactive bone handles for one Skeleton3D.
##
## Handles rotate bones with pure FK; the rest of the pose (reset, restore from
## a saved preset) is applied directly to the skeleton and picked up here.

signal bone_pose_edited
signal filter_changed(filter: int)

enum BoneFilter { ALL, MAJOR, NONE }

const MAX_HANDLES := 120

## Matched against normalised bone names ("LeftUpperArm" -> "leftupperarm").
## Covers Blender/Rigify, VRM and Mixamo naming conventions.
const MAJOR_KEYWORDS: PackedStringArray = [
	"hips", "pelvis", "spine", "chest", "upperchest", "torso",
	"neck", "head", "clavicle", "shoulder",
	"upperarm", "arm", "forearm", "lowerarm", "elbow", "hand", "wrist",
	"upperleg", "thigh", "leg", "calf", "shin", "lowerleg", "knee",
	"foot", "ankle", "toe", "ball",
]

## Too small or too many to be useful as mannequin handles.
const EXCLUDED_KEYWORDS: PackedStringArray = [
	"finger", "thumb", "index", "middle", "ring", "pinky", "little",
	"eye", "jaw", "tongue", "breast", "tail", "hair", "skirt", "ear",
]

@export var filter: BoneFilter = BoneFilter.MAJOR
@export var handle_radius := 0.017

var skeleton: Skeleton3D
var skeleton_path := NodePath()
var _handles: Array[BoneHandle] = []
var _materials: Dictionary = {}


func setup(target: Skeleton3D, relative_path: NodePath) -> void:
	skeleton = target
	skeleton_path = relative_path
	name = "SkeletonPoser"
	_build_materials()
	# Newly created skeletons start with identity bone poses instead of rest
	# poses, and cached global poses can be stale. Normalising to rest gives
	# handles (and "reset pose") a correct, predictable basis.
	skeleton.reset_bone_poses()
	skeleton.force_update_all_bone_transforms()
	rebuild()


func _build_materials() -> void:
	if not _materials.is_empty():
		return
	var palette := {
		BoneHandle.NORMAL_COLOR: BoneHandle.NORMAL_COLOR,
		BoneHandle.HOVER_COLOR: BoneHandle.HOVER_COLOR,
		BoneHandle.ACTIVE_COLOR: BoneHandle.ACTIVE_COLOR,
	}
	for color in palette:
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		# Joints sit inside the mesh; drawing handles on top keeps them usable.
		material.no_depth_test = true
		material.render_priority = 2
		_materials[color] = material


func set_filter(new_filter: BoneFilter) -> void:
	if filter == new_filter:
		return
	filter = new_filter
	rebuild()
	filter_changed.emit(filter)


func rebuild() -> void:
	for handle in _handles:
		if is_instance_valid(handle):
			handle.queue_free()
	_handles.clear()

	if skeleton == null or not is_instance_valid(skeleton) or filter == BoneFilter.NONE:
		return

	var candidates: Array[int] = []
	for bone in skeleton.get_bone_count():
		if _should_show_bone(bone):
			candidates.append(bone)
	if candidates.size() > MAX_HANDLES:
		candidates.resize(MAX_HANDLES)

	for bone in candidates:
		var handle := BoneHandle.new()
		handle.name = "Handle_%s" % skeleton.get_bone_name(bone)
		add_child(handle)
		handle.setup(skeleton, bone, handle_radius, _materials)
		_handles.append(handle)


func _should_show_bone(bone: int) -> bool:
	var normalised := _normalise_bone_name(skeleton.get_bone_name(bone))
	if filter == BoneFilter.ALL:
		return true
	if _matches_any(normalised, EXCLUDED_KEYWORDS):
		return false
	return _matches_any(normalised, MAJOR_KEYWORDS)


static func _normalise_bone_name(bone_name: String) -> String:
	var normalised := bone_name.to_lower()
	for token in ["mixamorig", "j_bip_", "def-", "org-", "_", "-", " ", ".", ":", "|"]:
		normalised = normalised.replace(token, "")
	return normalised


static func _matches_any(normalised: String, keywords: PackedStringArray) -> bool:
	for keyword in keywords:
		if normalised.contains(keyword):
			return true
	return false


func _process(_delta: float) -> void:
	# Bone transforms can change from a preset restore, so keep handles glued
	# to their joints whenever the skeleton is posed by anything.
	for handle in _handles:
		if is_instance_valid(handle):
			handle.sync_transform()


func handle_count() -> int:
	return _handles.size()


func handle_for_bone(bone: int) -> BoneHandle:
	for handle in _handles:
		if is_instance_valid(handle) and handle.bone_index == bone:
			return handle
	return null


func get_bone_count() -> int:
	return skeleton.get_bone_count() if is_instance_valid(skeleton) else 0


# --- Pose editing ----------------------------------------------------------

func reset_pose() -> void:
	if not is_instance_valid(skeleton):
		return
	skeleton.reset_bone_poses()
	skeleton.force_update_all_bone_transforms()
	bone_pose_edited.emit()


func reset_bone(bone_name_to_reset: String) -> bool:
	if not is_instance_valid(skeleton):
		return false
	var bone := skeleton.find_bone(bone_name_to_reset)
	if bone < 0:
		return false
	skeleton.reset_bone_pose(bone)
	skeleton.force_update_all_bone_transforms()
	bone_pose_edited.emit()
	return true


## Bone local poses, rest included, as JSON-friendly data.
func capture_bone_poses() -> Array:
	var entries: Array = []
	if not is_instance_valid(skeleton):
		return entries
	for bone in skeleton.get_bone_count():
		var pose := skeleton.get_bone_pose(bone)
		var rotation := pose.basis.get_rotation_quaternion()
		entries.append({
			"name": skeleton.get_bone_name(bone),
			"position": [pose.origin.x, pose.origin.y, pose.origin.z],
			"rotation": [rotation.x, rotation.y, rotation.z, rotation.w],
			"scale": [pose.basis.get_scale().x, pose.basis.get_scale().y, pose.basis.get_scale().z],
		})
	return entries


func apply_bone_poses(entries: Array) -> int:
	if not is_instance_valid(skeleton):
		return 0
	var applied := 0
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var data := entry as Dictionary
		var bone := skeleton.find_bone(String(data.get("name", "")))
		if bone < 0:
			continue
		var position := _to_vector3(data.get("position", [0, 0, 0]))
		var scale := _to_vector3(data.get("scale", [1, 1, 1]))
		var rotation := Quaternion.IDENTITY
		var raw_rotation: Variant = data.get("rotation", [0, 0, 0, 1])
		if raw_rotation is Array and (raw_rotation as Array).size() == 4:
			rotation = Quaternion(
					float(raw_rotation[0]), float(raw_rotation[1]),
					float(raw_rotation[2]), float(raw_rotation[3]))
		var basis := Basis(rotation).scaled(scale)
		skeleton.set_bone_pose(bone, Transform3D(basis, position))
		applied += 1
	skeleton.force_update_all_bone_transforms()
	bone_pose_edited.emit()
	return applied


static func _to_vector3(value: Variant) -> Vector3:
	if value is Array and (value as Array).size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO
