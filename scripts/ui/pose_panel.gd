class_name PosePanel
extends VRPanel
## The floating wrist-free control panel: model browser, blend shape sliders and
## pose actions. Everything is grabbed directly, so controllers and hands use
## exactly the same gestures.

enum Tab { MODELS, SHAPES, POSES }

const MODEL_ROWS := 3
const SHAPE_ROWS := 4
const POSE_ROWS := 4
const MODEL_ROW_STEP := 0.054
const SHAPE_ROW_STEP := 0.060
const PAGING_Y := -0.176

var library: ModelLibrary
var rig: CharacterRig

var _tab := Tab.MODELS
var _tab_buttons: Array[UIButton3D] = []
var _models: Array[Dictionary] = []
var _model_page := 0
var _shape_page := 0
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
	var labels := ["Models", "Shapes", "Poses"]
	for index in labels.size():
		var button := UIButton3D.new()
		add_child(button)
		button.position = Vector3(-0.172 + index * 0.172, 0.140, 0.001)
		button.setup(labels[index], Vector2(0.168, 0.036), 0.016)
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
	# Buttons emit `pressed` from inside their own grab handling, and loading the
	# model frees every widget on the panel. Rebuilding re-entrantly in the middle
	# of that signal is what could hang the panel, so collapse nested requests
	# into one rebuild.
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


# --- Models ----------------------------------------------------------------

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


## Lists every directory that was searched and what was found there, so an empty
## list on the headset says whether the folder is missing or just empty.
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
	var decrease := add_button("Scale -", Vector3(-0.155, -0.082, 0), Vector2(0.14, 0.034), 0.015)
	decrease.enabled = has_model
	decrease.pressed.connect(_on_scale_step.bind(-1))

	var readout := add_button(_scale_text(), Vector3(0.0, -0.082, 0), Vector2(0.13, 0.034), 0.015)
	readout.enabled = false

	var increase := add_button("Scale +", Vector3(0.155, -0.082, 0), Vector2(0.14, 0.034), 0.015)
	increase.enabled = has_model
	increase.pressed.connect(_on_scale_step.bind(1))

	var fit := add_button("Fit to 1.6 m", Vector3(0, -0.132, 0), Vector2(0.30, 0.034), 0.015)
	fit.enabled = has_model
	fit.pressed.connect(_on_fit_height)


func _scale_text() -> String:
	if rig == null or not rig.has_model():
		return "--"
	return "%d%%" % int(round(rig.get_scale_multiplier() * 100.0))


func _on_scale_step(direction: int) -> void:
	if rig == null or not rig.has_model():
		return
	var factor := 1.15 if direction > 0 else 1.0 / 1.15
	rig.set_scale_multiplier(rig.get_scale_multiplier() * factor)
	set_status("Character scale: %s" % _scale_text())
	refresh()


func _on_fit_height() -> void:
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


func _on_rescan() -> void:
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


# --- Blend shapes ----------------------------------------------------------

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


func _on_reset_shapes() -> void:
	if rig == null:
		return
	rig.blend_shapes.reset_all()
	set_status("All blend shapes reset.")
	refresh()


# --- Poses -----------------------------------------------------------------

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


func _on_reset_pose() -> void:
	if rig == null:
		return
	rig.reset_pose()
	set_status("Pose reset to rest.")
	refresh()


func _on_cycle_bone_filter() -> void:
	if rig == null or rig.posers.is_empty():
		return
	var next := (int(rig.posers[0].filter) + 1) % 3
	for poser in rig.posers:
		if is_instance_valid(poser):
			poser.set_filter(next)
	if _bone_filter_button != null:
		_bone_filter_button.set_text(_bone_filter_text())
	set_status(_bone_filter_text())


func _on_save_pose() -> void:
	if rig == null or not rig.has_model():
		return
	var path := PoseStore.save(rig.capture_pose())
	if path.is_empty():
		set_status("Could not write the pose file.", true)
		return
	set_status("Pose saved: %s" % path.get_file())
	refresh()


func _on_load_pose(path: String) -> void:
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


# --- Shared widgets --------------------------------------------------------

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
