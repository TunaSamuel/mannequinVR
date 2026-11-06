class_name CharacterRig
extends Node3D
## Owns the loaded character: its transform, skeletons, bone handles and blend
## shapes. Also provides the grab target that moves/scales the character.

signal model_changed(info: Dictionary)
signal model_cleared
signal status_message(message: String)
signal pose_edited

const TARGET_HEIGHT := 1.7
const MIN_NATURAL_HEIGHT := 0.6
const MAX_NATURAL_HEIGHT := 2.4
const GRAB_MARGIN := 0.04

var model_root: Node3D
var posing_root: Node3D
var posers: Array[SkeletonPoser] = []
var blend_shapes := BlendShapeSet.new()

var model_source := ""
var model_name := ""
var model_stats: Dictionary = {}
var model_warnings: PackedStringArray = []

var _grabs: Array[XRInteractor] = []
var _single_offset_local := Vector3.ZERO
var _single_start_basis := Basis()
var _single_start_interactor_basis := Basis()
var _single_start_scale := 1.0
var _dual_start_distance := 1.0
var _dual_start_scale := 1.0
var _dual_start_rotation := Basis()
var _dual_midpoint_local := Vector3.ZERO
var _dual_start_axis := Vector3.ZERO
var _hovered := false


func _ready() -> void:
	_ensure_containers()
	add_to_group("grab_target")


func _ensure_containers() -> void:
	if model_root == null:
		model_root = Node3D.new()
		model_root.name = "ModelRoot"
		add_child(model_root)
	if posing_root == null:
		posing_root = Node3D.new()
		posing_root.name = "Posing"
		add_child(posing_root)


func has_model() -> bool:
	return model_root != null and model_root.get_child_count() > 0


# --- Loading ---------------------------------------------------------------

## Loads a character. Returns the loader result so callers can show an error.
func load_model(path: String) -> ModelLoader.Result:
	var result := ModelLoader.load_from_path(path)
	if not result.ok:
		status_message.emit(result.error)
		return result

	install_model(result.scene, path, path.get_file().get_basename(), result.stats)
	for warning in result.warnings:
		push_warning("Model '%s': %s" % [model_name, warning])
	return result


## Installs an already-built model scene. Used by the loader and by tests.
func install_model(scene: Node3D, source_path: String = "", display_name: String = "",
		stats: Dictionary = {}) -> Dictionary:
	_ensure_containers()
	unload()

	model_source = source_path
	model_name = display_name if not display_name.is_empty() else scene.name
	model_stats = stats if not stats.is_empty() else ModelLoader.analyze(scene)
	model_warnings = ModelLoader.warnings_for(model_stats)

	model_root.add_child(scene)
	_fit_model_to_floor(model_stats)

	# One poser per skeleton: most characters have one, but multi-part imports
	# can bring several.
	for skeleton in ModelLoader.collect_skeletons(scene):
		var poser := SkeletonPoser.new()
		posing_root.add_child(poser)
		poser.setup(skeleton, model_root.get_path_to(skeleton))
		poser.bone_pose_edited.connect(_on_pose_edited)
		posers.append(poser)

	blend_shapes.collect(scene)
	pose_edited.emit()

	var info := get_info()
	model_changed.emit(info)
	return info


func unload() -> void:
	_grabs.clear()
	for poser in posers:
		if is_instance_valid(poser):
			poser.get_parent().remove_child(poser)
			poser.queue_free()
	posers.clear()
	blend_shapes = BlendShapeSet.new()
	if model_root != null:
		for child in model_root.get_children():
			model_root.remove_child(child)
			child.queue_free()
	model_source = ""
	model_name = ""
	model_stats = {}
	model_warnings = PackedStringArray()
	model_cleared.emit()


## Centers the model on the rig origin, puts its feet on the floor and scales
## wildly-sized characters to a comfortable human-ish height.
func _fit_model_to_floor(stats: Dictionary) -> void:
	if model_root.get_child_count() == 0:
		return
	var instance := model_root.get_child(0) as Node3D
	if instance == null:
		return
	var bounds: AABB = stats.get("aabb", AABB())
	if not bool(stats.get("has_bounds", false)) or bounds.size == Vector3.ZERO:
		instance.position = Vector3.ZERO
		scale = Vector3.ONE
		return

	var height := bounds.size.y
	var fit_scale := 1.0
	if height > 0.001 and (height < MIN_NATURAL_HEIGHT or height > MAX_NATURAL_HEIGHT):
		fit_scale = clampf(TARGET_HEIGHT / height, 0.1, 10.0)

	instance.position = Vector3(
		-bounds.position.x - bounds.size.x * 0.5,
		-bounds.position.y,
		-bounds.position.z - bounds.size.z * 0.5,
	)
	scale = Vector3.ONE * fit_scale


func get_info() -> Dictionary:
	var handle_count := 0
	for poser in posers:
		if is_instance_valid(poser):
			handle_count += poser.handle_count()
	return {
		"name": model_name,
		"source": model_source,
		"stats": model_stats,
		"warnings": model_warnings,
		"handles": handle_count,
		"blend_shapes": blend_shapes.count(),
		"posers": posers.size(),
	}


# --- Pose presets ----------------------------------------------------------

func capture_pose() -> Dictionary:
	var skeletons_data: Array = []
	for poser in posers:
		if not is_instance_valid(poser) or poser.skeleton == null:
			continue
		skeletons_data.append({
			"path": String(poser.skeleton_path),
			"bones": poser.capture_bone_poses(),
		})
	var rotation := global_transform.basis.get_rotation_quaternion()
	var stamp := Time.get_datetime_dict_from_system()
	return {
		"app": "vr-character-poser",
		"version": PoseStore.FORMAT_VERSION,
		"model_name": model_name,
		"model_source": model_source,
		"created_label": "%04d-%02d-%02d %02d:%02d" % [
			stamp["year"], stamp["month"], stamp["day"], stamp["hour"], stamp["minute"],
		],
		"character": {
			"position": [position.x, position.y, position.z],
			"rotation": [rotation.x, rotation.y, rotation.z, rotation.w],
			"scale": scale.x,
		},
		"skeletons": skeletons_data,
		"blend_shapes": blend_shapes.capture(),
	}


## Applies a pose document. Returns a summary for the UI.
func apply_pose(document: Dictionary) -> Dictionary:
	var summary := {"bones": 0, "shapes": 0, "missing_skeletons": 0}

	var character: Variant = document.get("character", {})
	if typeof(character) == TYPE_DICTIONARY:
		var character_data := character as Dictionary
		var position_data: Variant = character_data.get("position", [])
		if position_data is Array and (position_data as Array).size() == 3:
			position = Vector3(float(position_data[0]), float(position_data[1]), float(position_data[2]))
		var rotation_data: Variant = character_data.get("rotation", [])
		if rotation_data is Array and (rotation_data as Array).size() == 4:
			var rotation := Quaternion(
					float(rotation_data[0]), float(rotation_data[1]),
					float(rotation_data[2]), float(rotation_data[3]))
			var uniform_scale := float(character_data.get("scale", scale.x))
			global_transform = Transform3D(Basis(rotation).scaled(Vector3.ONE * uniform_scale), position)

	for entry in (document.get("skeletons", []) as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var record := entry as Dictionary
		var wanted_path := String(record.get("path", ""))
		var matched := false
		for poser in posers:
			if not is_instance_valid(poser):
				continue
			if not wanted_path.is_empty() and String(poser.skeleton_path) != wanted_path:
				continue
			summary["bones"] += poser.apply_bone_poses(record.get("bones", []))
			matched = true
		if not matched:
			summary["missing_skeletons"] += 1

	summary["shapes"] = blend_shapes.apply(document.get("blend_shapes", []))
	pose_edited.emit()
	return summary


func reset_pose() -> void:
	for poser in posers:
		if is_instance_valid(poser):
			poser.reset_pose()
	pose_edited.emit()


# --- Grab target interface -------------------------------------------------

func can_grab(point: Vector3) -> bool:
	if not has_model():
		return false
	return world_bounds().grow(GRAB_MARGIN).has_point(point)


func get_grab_priority() -> int:
	return 5


## Two hands can hold the character at once for scaling and rotation.
func accepts_multiple_grabs() -> bool:
	return true


func get_grab_distance(point: Vector3) -> float:
	if not has_model():
		return INF
	var bounds := world_bounds()
	if bounds.has_point(point):
		return 0.0
	return bounds.get_center().distance_to(point)


func set_hover(hovered: bool) -> void:
	_hovered = hovered


func is_hovered() -> bool:
	return _hovered


func is_grabbed() -> bool:
	return not _grabs.is_empty()


func world_bounds() -> AABB:
	if not has_model():
		return AABB()
	var model := model_root.get_child(0) as Node3D
	if model == null:
		return AABB()
	var local_bounds := _subtree_bounds(model)
	return _transform_bounds(local_bounds, model_root.global_transform)


func begin_grab(interactor: XRInteractor) -> void:
	if not has_model() or _grabs.has(interactor):
		return
	_grabs.append(interactor)
	if _grabs.size() == 1:
		_start_single(interactor)
	else:
		_start_dual()


func drag_grab(interactor: XRInteractor) -> void:
	if not _grabs.has(interactor):
		return
	if _grabs.size() == 1:
		_drag_single(interactor)
	else:
		_drag_dual()


func end_grab(interactor: XRInteractor) -> void:
	_grabs.erase(interactor)
	if _grabs.size() == 1:
		# Hand over cleanly to the remaining hand instead of snapping.
		_start_single(_grabs[0])


func _start_single(interactor: XRInteractor) -> void:
	var s := maxf(scale.x, 0.0001)
	_single_start_scale = s
	_single_start_basis = global_transform.basis.orthonormalized()
	_single_start_interactor_basis = interactor.get_grab_basis().orthonormalized()
	_single_offset_local = (_single_start_basis.inverse() * (interactor.get_grab_point() - global_position)) / s


func _drag_single(interactor: XRInteractor) -> void:
	var current := interactor.get_grab_basis().orthonormalized()
	var delta := (current * _single_start_interactor_basis.inverse()).orthonormalized()
	var rotation := (delta * _single_start_basis).orthonormalized()
	var scaled_basis := rotation.scaled(Vector3.ONE * _single_start_scale)
	var offset := rotation * (_single_offset_local * _single_start_scale)
	global_transform = Transform3D(scaled_basis, interactor.get_grab_point() - offset)


func _start_dual() -> void:
	var first := _grabs[0].get_grab_point()
	var second := _grabs[1].get_grab_point()
	var midpoint := (first + second) * 0.5
	_dual_start_distance = maxf(first.distance_to(second), 0.001)
	_dual_start_scale = maxf(scale.x, 0.0001)
	_dual_start_rotation = global_transform.basis.orthonormalized()
	_dual_start_axis = Vector3(second.x - first.x, 0.0, second.z - first.z)
	_dual_midpoint_local = (_dual_start_rotation.inverse() * (midpoint - global_position)) / _dual_start_scale


func _drag_dual() -> void:
	var first := _grabs[0].get_grab_point()
	var second := _grabs[1].get_grab_point()
	var midpoint := (first + second) * 0.5
	var distance := maxf(first.distance_to(second), 0.001)
	var new_scale := clampf(_dual_start_scale * (distance / _dual_start_distance), 0.05, 20.0)

	var yaw := 0.0
	var flat_axis := Vector3(second.x - first.x, 0.0, second.z - first.z)
	if flat_axis.length() > 0.02 and _dual_start_axis.length() > 0.02:
		yaw = _dual_start_axis.signed_angle_to(flat_axis, Vector3.UP)
	var rotation := (_dual_start_rotation * Basis(Vector3.UP, yaw)).orthonormalized()
	var basis := rotation.scaled(Vector3.ONE * new_scale)
	global_transform = Transform3D(basis, midpoint - rotation * (_dual_midpoint_local * new_scale))


# --- Helpers ---------------------------------------------------------------

func _on_pose_edited() -> void:
	pose_edited.emit()


func _subtree_bounds(root: Node3D) -> AABB:
	var bounds := AABB()
	var has_bounds := false
	var stack: Array = [[root, Transform3D()]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var node: Node = item[0]
		var parent_transform: Transform3D = item[1]
		var transform := parent_transform
		if node is Node3D:
			transform = parent_transform * (node as Node3D).transform
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var mesh_bounds := _transform_bounds((node as MeshInstance3D).mesh.get_aabb(), transform)
			bounds = mesh_bounds if not has_bounds else bounds.merge(mesh_bounds)
			has_bounds = true
		for child in node.get_children():
			stack.append([child, transform])
	return bounds if has_bounds else AABB()


func _transform_bounds(local_bounds: AABB, transform: Transform3D) -> AABB:
	if local_bounds.size == Vector3.ZERO:
		return AABB(transform * local_bounds.position, Vector3.ZERO)
	var result := AABB()
	for corner in range(8):
		var point := local_bounds.position + Vector3(
				local_bounds.size.x * float(corner & 1),
				local_bounds.size.y * float((corner >> 1) & 1),
				local_bounds.size.z * float((corner >> 2) & 1))
		var world := transform * point
		result = AABB(world, Vector3.ZERO) if corner == 0 else result.expand(world)
	return result
