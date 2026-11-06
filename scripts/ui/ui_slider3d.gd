class_name UISlider3D
extends Node3D
## A grab-and-slide value control for blend shape weights. Pinch/grip anywhere
## on the track and drag sideways; the value follows the grab point.

signal value_changed(value: float)

const GRAB_TOLERANCE := 0.032

var length := 0.2
var font_height := 0.015
var value := 0.0

var _rail: MeshInstance3D
var _fill: MeshInstance3D
var _knob: MeshInstance3D
var _label: Label3D
var _title := ""
var _grabbed_by: XRInteractor
var _hovered := false


func setup(slider_title: String, track_length: float, text_height: float = 0.015) -> UISlider3D:
	length = track_length
	font_height = text_height
	_title = slider_title

	_rail = UIStyle.quad(Vector2(length, 0.006), UIStyle.COLOR_TRACK, 2)
	add_child(_rail)

	_fill = UIStyle.quad(Vector2(length, 0.006), UIStyle.COLOR_FILL, 3)
	_fill.position.z = 0.0008
	add_child(_fill)

	var knob_mesh := SphereMesh.new()
	knob_mesh.radius = 0.0125
	knob_mesh.height = 0.025
	knob_mesh.radial_segments = 12
	knob_mesh.rings = 6
	_knob = MeshInstance3D.new()
	_knob.mesh = knob_mesh
	_knob.material_override = UIStyle.unshaded_material(UIStyle.COLOR_KNOB)
	_knob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_knob.position.z = 0.004
	add_child(_knob)

	_label = UIStyle.make_label("", font_height, UIStyle.COLOR_TEXT_DIM)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_label.width = length / UIStyle.FONT_PIXEL_SIZE
	_label.position = Vector3(0, 0.028, 0.0025)
	add_child(_label)

	add_to_group("grab_target")
	_update_visuals()
	return self


func set_value(new_value: float, notify: bool = false) -> void:
	var clamped := clampf(new_value, 0.0, 1.0)
	if is_equal_approx(clamped, value):
		return
	value = clamped
	_update_visuals()
	if notify:
		value_changed.emit(value)


func get_display_text() -> String:
	return "%s   %d%%" % [_title, int(round(value * 100.0))]


func _update_visuals() -> void:
	if _fill == null:
		return
	var filled := maxf(value, 0.001)
	_fill.scale = Vector3(filled, 1.0, 1.0)
	_fill.position.x = -length * 0.5 + length * value * 0.5
	_knob.position.x = -length * 0.5 + length * value
	if _label != null:
		_label.text = get_display_text()
		_label.modulate = UIStyle.COLOR_TEXT if _grabbed_by != null else UIStyle.COLOR_TEXT_DIM


func _value_from_point(point: Vector3) -> float:
	var local := to_local(point)
	return clampf((local.x + length * 0.5) / maxf(length, 0.001), 0.0, 1.0)


# --- Grab target interface -------------------------------------------------

func can_grab(point: Vector3) -> bool:
	if is_grabbed():
		return false
	var local := to_local(point)
	return absf(local.z) <= GRAB_TOLERANCE \
			and absf(local.y) <= 0.028 \
			and absf(local.x) <= length * 0.5 + 0.015


func get_grab_priority() -> int:
	return 40


func get_grab_distance(point: Vector3) -> float:
	var local := to_local(point)
	var outside := Vector2(
		maxf(absf(local.x) - length * 0.5, 0.0),
		maxf(absf(local.y) - 0.010, 0.0))
	return outside.length() + absf(local.z)


func is_grabbed() -> bool:
	return _grabbed_by != null


func set_hover(hovered: bool) -> void:
	if _hovered == hovered:
		return
	_hovered = hovered
	if _knob != null:
		_knob.material_override = UIStyle.unshaded_material(
				UIStyle.COLOR_FILL if hovered else UIStyle.COLOR_KNOB)


func begin_grab(interactor: XRInteractor) -> void:
	_grabbed_by = interactor
	set_value(_value_from_point(interactor.get_grab_point()), true)
	_update_visuals()


func drag_grab(interactor: XRInteractor) -> void:
	if _grabbed_by != interactor:
		return
	set_value(_value_from_point(interactor.get_grab_point()), true)


func end_grab(_interactor: XRInteractor) -> void:
	_grabbed_by = null
	_update_visuals()
