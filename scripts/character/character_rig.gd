class_name CharacterRig
extends Node3D
## Owns the loaded character: its transform, skeletons, bone handles and blend
## shapes. Also provides the grab target that moves/scales the character.

signal model_changed(info: Dictionary)
signal model_cleared
signal status_message(message: String)
signal pose_edited

const TARGET_HEIGHT := 1.6
const MIN_NATURAL_HEIGHT := 0.55
const MAX_NATURAL_HEIGHT := 2.0
const GRAB_MARGIN := 0.04
const MIN_SCALE_MULTIPLIER := 0.2
const MAX_SCALE_MULTIPLIER := 3.0
## World-space floor height (CharacterRoot Y) the Floor slider dials.
const MIN_FLOOR_Y := -0.25
const MAX_FLOOR_Y := 2.0
const UNDO_LIMIT := 40

var model_root: Node3D
var posing_root: Node3D
var posers: Array[SkeletonPoser] = []
var blend_shapes := BlendShapeSet.new()

var model_source := ""
var model_name := ""
var base_scale := 1.0
var scale_multiplier := 1.0
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
var _parts: Array[MeshInstance3D] = []
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _history_suspended := false


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


func load_model(path: String) -> ModelLoader.Result:
	var result := ModelLoader.load_from_path(path)
	if not result.ok:
		status_message.emit(result.error)
		return result
	install_model(result.scene, path, path.get_file().get_basename(), result.stats)
	for warning in result.warnings:
		push_warning("Model '%s': %s" % [model_name, warning])
	return result


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
	for skeleton in ModelLoader.collect_skeletons(scene):
		var poser := SkeletonPoser.new()
		posing_root.add_child(poser)
		poser.setup(skeleton, model_root.get_path_to(skeleton))
		poser.bone_pose_edited.connect(_on_pose_edited)
		posers.append(poser)
	blend_shapes.collect(scene)
	_collect_parts(scene)
	_undo_stack.clear()
	_redo_stack.clear()
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
	_parts.clear()
	if model_root != null:
		for child in model_root.get_children():
			model_root.remove_child(child)
			child.queue_free()
	model_source = ""
	model_name = ""
	model_stats = {}
	model_warnings = PackedStringArray()
	base_scale = 1.0
	scale_multiplier = 1.0
	_undo_stack.clear()
	_redo_stack.clear()
	_apply_scale()
	model_cleared.emit()
