class_name BoneHandle
extends Node3D
## A small grabbable sphere sitting on a skeleton joint.
##
## Dragging a handle rotates the bone in place (pure forward kinematics), using
## the rotation delta of the grabbing hand/controller. Children follow because
## only the local bone pose is changed.

const NORMAL_COLOR := Color(0.35, 0.85, 0.95, 0.85)
const HOVER_COLOR := Color(1.0, 0.85, 0.35, 0.95)
const ACTIVE_COLOR := Color(1.0, 0.45, 0.25, 1.0)

enum Highlight { NONE, HOVER, GRABBED }

var bone_index := -1
var bone_name := ""
var grab_radius := 0.042

var _skeleton: Skeleton3D
var _mesh_instance: MeshInstance3D
var _highlight := Highlight.NONE
var _materials: Dictionary = {}
var _grabbed_by: XRInteractor
var _start_bone_pose := Transform3D()
var _start_interactor_basis := Basis()
var _start_skeleton_basis := Basis()


func setup(skeleton: Skeleton3D, index: int, radius: float, materials: Dictionary) -> void:
	_skeleton = skeleton
	bone_index = index
	bone_name = skeleton.get_bone_name(index)
	grab_radius = radius + 0.024
	_materials = materials

	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	sphere.material = materials[NORMAL_COLOR]

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = sphere
	_mesh_instance.name = "BoneHandleVisual"
	# Joints often sit inside the mesh, so handles render on top of the body.
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance)

	add_to_group("grab_target")
	sync_transform()


func _exit_tree() -> void:
	# Handles are disposable: never keep a grab alive on a freed handle.
	_grabbed_by = null


## Moves the handle onto its joint, keeping a constant world-space size even
## when the character is scaled.
func sync_transform() -> void:
	if not is_instance_valid(_skeleton):
		return
	var bone_pose := _skeleton.get_bone_global_pose(bone_index)
	var skeleton_basis := _skeleton.global_transform.basis.orthonormalized()
	var world_basis := (skeleton_basis * bone_pose.basis.orthonormalized()).orthonormalized()
	global_transform = Transform3D(world_basis, _skeleton.global_transform * bone_pose.origin)


func is_bone_pose_valid() -> bool:
	return is_instance_valid(_skeleton) and bone_index >= 0 and bone_index < _skeleton.get_bone_count()


func set_highlight(highlight: Highlight) -> void:
	if _highlight == highlight:
		return
	_highlight = highlight
	if _mesh_instance == null:
		return
	match highlight:
		Highlight.HOVER:
			_mesh_instance.material_override = _materials[HOVER_COLOR]
		Highlight.GRABBED:
			_mesh_instance.material_override = _materials[ACTIVE_COLOR]
		_:
			_mesh_instance.material_override = _materials[NORMAL_COLOR]


func is_grabbed() -> bool:
	return _grabbed_by != null


# --- Grab target interface -------------------------------------------------

func can_grab(point: Vector3) -> bool:
	if not is_bone_pose_valid() or is_grabbed():
		return false
	return global_position.distance_to(point) <= grab_radius


func get_grab_priority() -> int:
	return 20


func get_grab_distance(point: Vector3) -> float:
	return global_position.distance_to(point)


func begin_grab(interactor: XRInteractor) -> void:
	if not is_bone_pose_valid():
		return
	_grabbed_by = interactor
	_start_bone_pose = _skeleton.get_bone_global_pose(bone_index)
	_start_interactor_basis = interactor.get_grab_basis().orthonormalized()
	_start_skeleton_basis = _skeleton.global_transform.basis.orthonormalized()
	set_highlight(Highlight.GRABBED)


func drag_grab(interactor: XRInteractor) -> void:
	if _grabbed_by != interactor or not is_bone_pose_valid():
		return
	var current_basis := interactor.get_grab_basis().orthonormalized()
	var world_delta := current_basis * _start_interactor_basis.inverse()
	# The physics/render delta is in world space; bone poses live in skeleton space.
	var local_delta := _start_skeleton_basis.inverse() * world_delta * _start_skeleton_basis

	var rest_scale := _start_bone_pose.basis.get_scale()
	var start_rotation := _start_bone_pose.basis.orthonormalized()
	var new_basis := (local_delta * start_rotation).orthonormalized().scaled(rest_scale)
	_skeleton.set_bone_global_pose(bone_index, Transform3D(new_basis, _start_bone_pose.origin))
	sync_transform()


func end_grab(_interactor: XRInteractor) -> void:
	_grabbed_by = null
	set_highlight(Highlight.NONE)
	_emit_pose_changed()


func _emit_pose_changed() -> void:
	var owner_rig := get_parent()
	while owner_rig != null:
		if owner_rig.has_signal("bone_pose_edited"):
			owner_rig.emit_signal("bone_pose_edited")
			return
		owner_rig = owner_rig.get_parent()
