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
const LOCKED_COLOR := Color(0.42, 0.45, 0.52, 0.55)

enum Highlight { NONE, HOVER, GRABBED, LOCKED }

var bone_index := -1
var bone_name := ""
var grab_radius := 0.042
var locked := false

var _skeleton: Skeleton3D
var _mesh_instance: MeshInstance3D
var _label: Label3D
var _highlight := Highlight.NONE
var _hovered := false
var _materials: Dictionary = {}
var _grabbed_by: XRInteractor
var _start_bone_pose := Transform3D()
var _start_interactor_basis := Basis()
var _start_skeleton_basis := Basis()


func setup(skeleton: Skeleton3D, index: int, radius: float, materials: Dictionary) -> void:
	_skeleton = skeleton
	bone_index = index
	bone_name = skeleton.get_bone_name(index)
	# Generous grab sphere so joints are easy to hit with the laser or a pinch.
	grab_radius = radius + 0.032
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

	_label = Label3D.new()
	_label.text = bone_name
	_label.font_size = 28
	_label.pixel_size = 0.00115
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0.0, radius + 0.028, 0.0)
	_label.modulate = Color(1.0, 0.95, 0.75, 1.0)
	_label.outline_modulate = Color(0.05, 0.06, 0.08, 0.9)
	_label.outline_size = 6
	_label.no_depth_test = true
	_label.render_priority = 4
	_label.visible = false
	add_child(_label)

	add_to_group("grab_target")
	sync_transform()


func _exit_tree() -> void:
	# Handles are disposable: never keep a grab alive on a freed handle.
	_grabbed_by = null
	set_highlight(Highlight.NONE)


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


func set_locked(value: bool) -> void:
	locked = value
	if locked and is_grabbed():
		# Drop any active grab so a locked joint cannot keep being rotated.
		var who := _grabbed_by
		_grabbed_by = null
		if who != null:
			pass
	_refresh_visual()


func toggle_locked() -> bool:
	set_locked(not locked)
	return locked


func set_highlight(highlight: Highlight) -> void:
	_highlight = highlight
	if _mesh_instance == null:
		return
	var color := NORMAL_COLOR
	match highlight:
		Highlight.HOVER:
			color = HOVER_COLOR
		Highlight.GRABBED:
			color = ACTIVE_COLOR
		Highlight.LOCKED:
			color = LOCKED_COLOR
		_:
			color = NORMAL_COLOR
	if locked and highlight != Highlight.GRABBED:
		color = LOCKED_COLOR
	_mesh_instance.material_override = _materials.get(color, _materials.get(NORMAL_COLOR))


func _refresh_visual() -> void:
	if is_grabbed():
		set_highlight(Highlight.GRABBED)
	elif locked:
		set_highlight(Highlight.LOCKED)
	elif _hovered:
		set_highlight(Highlight.HOVER)
	else:
		set_highlight(Highlight.NONE)
	if _label != null:
		_label.visible = _hovered or is_grabbed()


## Kept for parity with the other grab targets: highlighting the joint you are
## aiming at is the main cue that it can be posed.
func set_hover(hovered: bool) -> void:
	_hovered = hovered
	_refresh_visual()


func get_highlight() -> int:
	return int(_highlight)


func is_grabbed() -> bool:
	return _grabbed_by != null


# --- Grab target interface -------------------------------------------------

func can_grab(point: Vector3) -> bool:
	if not is_bone_pose_valid() or is_grabbed() or locked:
		return false
	return global_position.distance_to(point) <= grab_radius


func get_grab_radius() -> float:
	return grab_radius


## Laser hit test: the ray counts as a hit while it passes through the sphere
## that `can_grab` accepts, so the pointer point is always grabbable.
## Locked bones still ray-hit so the name label can show on hover.
func ray_hit(origin: Vector3, direction: Vector3, max_distance: float) -> float:
	if not is_bone_pose_valid() or is_grabbed():
		return INF
	return XRPointerRay.ray_sphere(origin, direction, global_position, grab_radius, max_distance)


func get_grab_priority() -> int:
	return 20


func get_grab_distance(point: Vector3) -> float:
	return global_position.distance_to(point)


func begin_grab(interactor: XRInteractor) -> void:
	if not is_bone_pose_valid() or locked:
		return
	_checkpoint_rig()
	_grabbed_by = interactor
	_start_bone_pose = _skeleton.get_bone_global_pose(bone_index)
	_start_interactor_basis = interactor.get_grab_basis().orthonormalized()
	_start_skeleton_basis = _skeleton.global_transform.basis.orthonormalized()
	set_highlight(Highlight.GRABBED)
	if _label != null:
		_label.visible = true


func drag_grab(interactor: XRInteractor) -> void:
	if _grabbed_by != interactor or not is_bone_pose_valid() or locked:
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
	_refresh_visual()
	_emit_pose_changed()


func _emit_pose_changed() -> void:
	var owner_rig := get_parent()
	while owner_rig != null:
		if owner_rig.has_signal("bone_pose_edited"):
			owner_rig.emit_signal("bone_pose_edited")
			return
		owner_rig = owner_rig.get_parent()


func _checkpoint_rig() -> void:
	var node: Node = self
	while node != null:
		if node.has_method("checkpoint"):
			node.call("checkpoint")
			return
		node = node.get_parent()
