class_name PosePanel
extends VRPanel
## The floating wrist-free control panel: model browser, blend shape sliders and
## pose actions. Everything is grabbed directly, so controllers and hands use
## exactly the same gestures.

enum Tab { MODELS, SHAPES, PARTS, POSES }

const MODEL_ROWS := 3
const SHAPE_ROWS := 4
const POSE_ROWS := 4
const PART_ROWS := 5
const MODEL_ROW_STEP := 0.054
const SHAPE_ROW_STEP := 0.060
const PART_ROW_STEP := 0.048
const PAGING_Y := -0.176

var library: ModelLibrary
var rig: CharacterRig

var _tab := Tab.MODELS
var _tab_buttons: Array[UIButton3D] = []
var _models: Array[Dictionary] = []
var _model_page := 0
var _shape_page := 0
var _part_page := 0
var _bone_filter_button: UIButton3D
var _tab_row_ready := false
var _refreshing := false
var _refresh_pending := false


func configure(model_library: ModelLibrary, character_rig: CharacterRig) -> void:
	library = model_library
	rig = character_rig
	if _content_root_missing():
		setup()
	_build_tabs()
	if rig != null:
		rig.model_changed.connect(_on_model_changed)
		rig.model_cleared.connect(refresh)
		rig.status_message.connect(_on_rig_status)
	refresh()


func _content_root_missing() -> bool:
	return content_root() == null


func _build_tabs() -> void:
	if _tab_row_ready:
		return
	_tab_row_ready = true
	var labels := ["Models", "Shapes", "Parts", "Poses"]
	for index in labels.size():
		var button := UIButton3D.new()
		add_child(button)
		button.position = Vector3(-0.2025 + index * 0.135, 0.140, 0.001)
		button.setup(labels[index], Vector2(0.128, 0.036), 0.015)
		button.pressed.connect(_on_tab_pressed.bind(index))
		_tab_buttons.append(button)
	_update_tab_buttons()


func _on_tab_pressed(_button: UIButton3D, index: int) -> void:
	_tab = index
	refresh()


func _update_tab_buttons() -> void:
	for index in _tab_buttons.size():
		_tab_buttons[index].selected = index == int(_tab)


func refresh() -> void:
	if content_root() == null:
		return
	if _refreshing:
		_refresh_pending = true
		return
	_refreshing = true
	clear_content()
	_update_tab_buttons()
	match _tab:
		Tab.MODELS:
			_build_models()
		Tab.SHAPES:
			_build_shapes()
		Tab.PARTS:
			_build_parts()
		Tab.POSES:
			_build_poses()
	_update_title()
	_refreshing = false
	if _refresh_pending:
		_refresh_pending = false
		refresh()


func _update_title() -> void:
	var suffix := ""
	if rig != null and rig.has_model() and not rig.model_name.is_empty():
		suffix = "  -  " + rig.model_name
	set_title("VR CHARACTER POSER" + suffix)


func _build_models() -> void:
	_scan_models()
	if _models.is_empty():
		_build_missing_models_hint()
	else:
		var start := _model_page * MODEL_ROWS
		for row in MODEL_ROWS:
			var index := start + row
			if index >= _models.size():
				break
			var entry := _models[index]
			var button := add_button(String(entry["name"]),
					Vector3(0, 0.096 - row * MODEL_ROW_STEP, 0), Vector2(0.50, 0.042))
			button.pressed.connect(_on_model_pressed.bind(String(entry["path"])))
			if rig != null and rig.model_source == String(entry["path"]):
				button.selected = true

	_build_scale_controls(rig != null and rig.has_model())
	var pages := _page_count(_models.size(), MODEL_ROWS)
	_add_paging(pages, _model_page, _on_model_page, "Rescan models", _on_rescan)


func _build_missing_models_hint() -> void:
	add_label("No models found. Looked in:", Vector3(0, 0.080, 0), 0.016,
			UIStyle.COLOR_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	var report: Array[Dictionary] = library.scan_report() if library != null else []
	var y := 0.044
	for index in mini(report.size(), 3):
		var item: Dictionary = report[index]
		var status := "%d model(s)" % int(item["models"]) if bool(item["exists"]) else "folder missing"
		add_label("%s - %s" % [String(item["display"]), status], Vector3(0, y, 0), 0.011,
				UIStyle.COLOR_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
		y -= 0.026
	add_label("Put .glb files in the project's models/ folder and export, or copy them to the app folder above.",
			Vector3(0, y - 0.004, 0), 0.011, UIStyle.COLOR_FILL, HORIZONTAL_ALIGNMENT_CENTER)


func _build_scale_controls(has_model: bool) -> void:
	# Floor height (model Y). Vertical placement is not on the right stick —
	# grip-grab the body for free move, or dial it here.
	var height := add_slider("Floor", Vector3(0.0, -0.048, 0), 0.44, 0.013)
	if has_model and rig != null:
		height.set_value(_floor_to_slider(rig.get_floor_y()), false)
	else:
		height.set_value(_floor_to_slider(0.0), false)
	height.value_changed.connect(_on_floor_slider)
	if not has_model:
		height.position.z = -1.0

	# Continuous scale via slider (0.2x .. 3.0x).
	var slider := add_slider("Scale", Vector3(0.0, -0.100, 0), 0.44, 0.013)
	if has_model and rig != null:
		var t := _multiplier_to_slider(rig.get_scale_multiplier())
		slider.set_value(t, false)
	else:
		slider.set_value(0.5, false)
	slider.value_changed.connect(_on_scale_slider)
	if not has_model:
		slider.position.z = -1.0

	var fit := add_button("Fit to 1.6 m", Vector3(0, -0.150, 0), Vector2(0.30, 0.032), 0.014)
	fit.enabled = has_model
	fit.pressed.connect(_on_fit_height)


func _scale_text() -> String:
	if rig == null or not rig.has_model():
		return "--"
	return "%d%%" % int(round(rig.get_scale_multiplier() * 100.0))


func _multiplier_to_slider(mult: float) -> float:
	var lo := CharacterRig.MIN_SCALE_MULTIPLIER
	var hi := CharacterRig.MAX_SCALE_MULTIPLIER
	return clampf((mult - lo) / maxf(hi - lo, 0.001), 0.0, 1.0)


func _slider_to_multiplier(t: float) -> float:
	var lo := CharacterRig.MIN_SCALE_MULTIPLIER
	var hi := CharacterRig.MAX_SCALE_MULTIPLIER
	return lerpf(lo, hi, clampf(t, 0.0, 1.0))


func _floor_to_slider(y: float) -> float:
	var lo := CharacterRig.MIN_FLOOR_Y
	var hi := CharacterRig.MAX_FLOOR_Y
	return clampf((y - lo) / maxf(hi - lo, 0.001), 0.0, 1.0)


func _slider_to_floor(t: float) -> float:
	var lo := CharacterRig.MIN_FLOOR_Y
	var hi := CharacterRig.MAX_FLOOR_Y
	return lerpf(lo, hi, clampf(t, 0.0, 1.0))


func _on_floor_slider(value: float) -> void:
	if rig == null or not rig.has_model():
		return
	rig.set_floor_y(_slider_to_floor(value))
	set_status("Floor height: %.2f m" % rig.get_floor_y())


## Continuous scale. Intentionally does NOT refresh the whole panel — rebuilding
## mid-drag would free the slider and feel like runaway scrolling.
func _on_scale_slider(value: float) -> void:
	if rig == null or not rig.has_model():
		return
	rig.set_scale_multiplier(_slider_to_multiplier(value))
	set_status("Character scale: %d%% (height %.2f m)" % [
		int(round(rig.get_scale_multiplier() * 100.0)),
		rig.world_height()])


func _on_fit_height(_button: UIButton3D = null) -> void:
	if rig == null or not rig.has_model():
		return
	if not rig.fit_to_height():
		set_status("Could not measure this model.", true)
		refresh()
		return
	set_status("Fitted to %.2f m tall." % rig.world_height())
	refresh()


func _on_model_pressed(_button: UIButton3D, path: String) -> void:
	if rig == null:
		return
	set_status("Loading %s..." % path.get_file())
	var result := rig.load_model(path)
	if not result.ok:
		set_status(result.error, true)
		refresh()
		return
	if library != null:
		library.mark_recent(path)
	_scan_models()
	var stats := rig.model_stats
	var message := "%s: %d bones, %d blend shapes" % [
		rig.model_name,
		int(stats.get("bones", 0)),
		int(stats.get("blend_shapes", 0)),
	]
	if not rig.model_warnings.is_empty():
		message = "! " + String(rig.model_warnings[0])
	set_status(message)
	_tab = Tab.SHAPES if int(stats.get("blend_shapes", 0)) > 0 else Tab.MODELS
	refresh()


func _on_model_page(delta: int) -> void:
	_model_page = maxi(_model_page + delta, 0)
	refresh()


func _on_rescan(_button: UIButton3D = null) -> void:
	_scan_models()
	set_status("Found %d model(s)." % _models.size())
	refresh()


func _scan_models() -> void:
	if library == null:
		_models.clear()
		return
	_models = library.scan()
	var pages := _page_count(_models.size(), MODEL_ROWS)
	_model_page = clampi(_model_page, 0, pages - 1)


func _build_shapes() -> void:
	if rig == null or not rig.has_model():
		add_label("Load a character first.", Vector3(0, 0.05, 0), 0.018,
				UIStyle.COLOR_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
		return
	var shapes := rig.blend_shapes
	var total := shapes.count()
	if total == 0:
		add_label("This model has no blend shapes.", Vector3(0, 0.05, 0), 0.018,
				UIStyle.COLOR_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
		return

	var pages := _page_count(total, SHAPE_ROWS)
	_shape_page = clampi(_shape_page, 0, pages - 1)
	var start := _shape_page * SHAPE_ROWS
	for row in SHAPE_ROWS:
		var index := start + row
		if index >= total:
			break
		var slider := add_slider(shapes.display_name(index),
				Vector3(0, 0.088 - row * SHAPE_ROW_STEP, 0), 0.44)
		slider.set_value(shapes.get_value(index))
		slider.value_changed.connect(_on_shape_changed.bind(index))

	_add_paging(pages, _shape_page, _on_shape_page, "Reset all", _on_reset_shapes)


func _on_shape_changed(value: float, index: int) -> void:
	if rig != null:
		rig.blend_shapes.set_value(index, value)


func _on_shape_page(delta: int) -> void:
	_shape_page = maxi(_shape_page + delta, 0)
	refresh()


func _on_reset_shapes(_button: UIButton3D = null) -> void:
	if rig == null:
		return
	rig.blend_shapes.reset_all()
	set_status("All blend shapes reset.")
	refresh()


func _build_parts() -> void:
	if rig == null or not rig.has_model():
		add_label("Load a character first.", Vector3(0, 0.05, 0), 0.018,
				UIStyle.COLOR_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
		return
	var total := rig.part_count()
	if total == 0:
		add_label("No mesh parts found on this model.", Vector3(0, 0.05, 0), 0.018,
				UIStyle.COLOR_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
		add_label("Export separate Blender objects for hideable pieces.",
				Vector3(0, 0.01, 0), 0.013, UIStyle.COLOR_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
		return

	var pages := _page_count(total, PART_ROWS)
	_part_page = clampi(_part_page, 0, pages - 1)
	var start := _part_page * PART_ROWS
	for row in PART_ROWS:
		var index := start + row
		if index >= total:
			break
		var visible := rig.is_part_visible(index)
		var label := _part_label(rig.part_name(index), visible)
		var button := add_button(label, Vector3(0, 0.096 - row * PART_ROW_STEP, 0),
				Vector2(0.50, 0.040), 0.015)
		button.selected = visible
		button.pressed.connect(_on_part_toggle.bind(index))

	var hide_all := add_button("Hide all", Vector3(-0.08, PAGING_Y + 0.038, 0), Vector2(0.12, 0.030), 0.013)
	hide_all.pressed.connect(_on_hide_all_parts)
	_add_paging(pages, _part_page, _on_part_page, "Show all", _on_show_all_parts)


func _part_label(name: String, visible: bool) -> String:
	var mark := "[on]  " if visible else "[off] "
	var clipped := name
	if clipped.length() > 28:
		clipped = clipped.substr(0, 25) + "..."
	return mark + clipped


func _on_part_toggle(_button: UIButton3D, index: int) -> void:
	if rig == null:
		return
	var visible := rig.toggle_part(index)
	set_status("%s %s" % ["Shown" if visible else "Hidden", rig.part_name(index)])
	refresh()


func _on_part_page(delta: int) -> void:
	_part_page = maxi(_part_page + delta, 0)
	refresh()


func _on_show_all_parts(_button: UIButton3D = null) -> void:
	if rig == null:
		return
	var n := rig.set_all_parts_visible(true)
	set_status("All %d parts shown." % n)
	refresh()


func _on_hide_all_parts(_button: UIButton3D = null) -> void:
	if rig == null:
		return
	var n := rig.set_all_parts_visible(false)
	set_status("All %d parts hidden." % n)
	refresh()


func _build_poses() -> void:
	var has_model := rig != null and rig.has_model()
	var reset_button := add_button("Reset pose", Vector3(-0.128, 0.090, 0), Vector2(0.24, 0.040))
	reset_button.enabled = has_model
	reset_button.pressed.connect(_on_reset_pose)

	_bone_filter_button = add_button(_bone_filter_text(), Vector3(-0.128, 0.036, 0),
			Vector2(0.24, 0.040))
	_bone_filter_button.enabled = has_model
	_bone_filter_button.pressed.connect(_on_cycle_bone_filter)

	var save_button := add_button("Save pose", Vector3(-0.128, -0.018, 0), Vector2(0.24, 0.040))
	save_button.enabled = has_model
	save_button.pressed.connect(_on_save_pose)

	add_label("Saved poses", Vector3(0.128, 0.118, 0), 0.014,
			UIStyle.COLOR_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	var poses := PoseStore.list_poses()
	if poses.is_empty():
		add_label("None yet", Vector3(0.128, 0.070, 0), 0.015,
				UIStyle.COLOR_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		for row in POSE_ROWS:
			if row >= poses.size():
				break
			var pose := poses[row]
			var label := "%s %s" % [String(pose["label"]), String(pose["model_name"]).left(10)]
			var button := add_button(label, Vector3(0.128, 0.085 - row * 0.052, 0),
					Vector2(0.24, 0.040), 0.014)
			button.enabled = has_model
			button.pressed.connect(_on_load_pose.bind(String(pose["path"])))
	add_label("Poses save to user://poses", Vector3(0, -0.130, 0), 0.012,
			UIStyle.COLOR_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)


func _bone_filter_text() -> String:
	var filter := SkeletonPoser.BoneFilter.MAJOR
	if rig != null and not rig.posers.is_empty() and is_instance_valid(rig.posers[0]):
		filter = rig.posers[0].filter
	var names := ["Handles: All", "Handles: Major", "Handles: Off"]
	return names[int(filter)]


func _on_reset_pose(_button: UIButton3D = null) -> void:
	if rig == null:
		return
	rig.reset_pose()
	set_status("Pose reset to rest.")
	refresh()


func _on_cycle_bone_filter(_button: UIButton3D = null) -> void:
	if rig == null or rig.posers.is_empty():
		set_status("Load a character before changing bone handles.", true)
		return
	var next := (int(rig.posers[0].filter) + 1) % 3
	var total_handles := 0
	for poser in rig.posers:
		if is_instance_valid(poser):
			poser.set_filter(next)
			total_handles += poser.handle_count()
	if _bone_filter_button != null:
		_bone_filter_button.set_text(_bone_filter_text())
	var names := ["All joints", "Major joints only", "Handles hidden"]
	set_status("%s (%d handles visible)" % [names[next], total_handles])


func _on_save_pose(_button: UIButton3D = null) -> void:
	if rig == null or not rig.has_model():
		return
	var path := PoseStore.save(rig.capture_pose())
	if path.is_empty():
		set_status("Could not write the pose file.", true)
		return
	set_status("Pose saved: %s" % path.get_file())
	refresh()


func _on_load_pose(_button: UIButton3D, path: String) -> void:
	if rig == null:
		return
	var document := PoseStore.read(path)
	if document.is_empty():
		set_status("Pose file could not be read.", true)
		return
	var summary := rig.apply_pose(document)
	var message := "Pose loaded: %d bones, %d shapes" % [
		int(summary["bones"]), int(summary["shapes"])]
	if int(summary["missing_skeletons"]) > 0:
		message += " (%d skeleton mismatch)" % int(summary["missing_skeletons"])
	set_status(message)
	refresh()


func _add_paging(pages: int, page: int, on_page: Callable, middle_text: String,
		on_middle: Callable) -> void:
	var previous := add_button("<", Vector3(-0.238, PAGING_Y, 0), Vector2(0.05, 0.032))
	previous.enabled = page > 0
	previous.pressed.connect(func(_button: UIButton3D) -> void: on_page.call(-1))

	add_label("%d / %d" % [page + 1, pages], Vector3(-0.15, PAGING_Y, 0), 0.014,
			UIStyle.COLOR_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)

	var middle := add_button(middle_text, Vector3(0.02, PAGING_Y, 0), Vector2(0.16, 0.032), 0.014)
	middle.pressed.connect(func(_button: UIButton3D) -> void: on_middle.call())

	var next := add_button(">", Vector3(0.235, PAGING_Y, 0), Vector2(0.05, 0.032))
	next.enabled = page < pages - 1
	next.pressed.connect(func(_button: UIButton3D) -> void: on_page.call(1))


static func _page_count(item_count: int, rows: int) -> int:
	return maxi(1, int(ceil(item_count / float(maxi(rows, 1)))))


func _on_model_changed(_info: Dictionary) -> void:
	refresh()


func _on_rig_status(message: String) -> void:
	set_status(message, true)
