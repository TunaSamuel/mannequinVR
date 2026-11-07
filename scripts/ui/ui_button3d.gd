class_name UIButton3D
extends Node3D
## A directly touchable/pinchable panel button.
##
## Controllers activate this with the **trigger** (select). Hands still use
## pinch. Grip is intentionally ignored so posing bones never clicks the UI.

signal pressed(button: UIButton3D)

const SURFACE_TOLERANCE := 0.035
const GRAB_PADDING := 0.006
## Visual press flash duration before returning to normal/selected colour.
const PRESS_FLASH_SEC := 0.12

var size := Vector2(0.18, 0.045)
var text_height := 0.019
var enabled := true:
	set(value):
		enabled = value
		_refresh()
var selected := false:
	set(value):
		selected = value
		_refresh()

var _background: MeshInstance3D
var _label: Label3D
var _text := ""
var _hovered := false
var _pressed := false
var _grabbed_by: XRInteractor
var _flash_left := 0.0


func setup(button_text: String, button_size: Vector2, height: float = 0.019) -> UIButton3D:
	size = button_size
	text_height = height

	_background = UIStyle.quad(size, UIStyle.COLOR_BUTTON, 2)
	add_child(_background)

	_label = UIStyle.make_label("", text_height, UIStyle.COLOR_TEXT)
	_label.width = size.x / UIStyle.FONT_PIXEL_SIZE
	_label.position = Vector3(0, 0, 0.0025)
	add_child(_label)

	set_text(button_text)
	add_to_group("grab_target")
	_refresh()
	return self


func set_text(value: String) -> void:
	_text = value
	if _label == null:
		return
	_label.text = value
	var max_width := size.x - 0.014
	var estimated := 0.0086 * value.length() * (text_height / 0.019)
	if estimated > max_width and value.length() > 0:
		var factor := clampf(max_width / estimated, 0.35, 1.0)
		var max_font := maxi(int(round(text_height / UIStyle.FONT_PIXEL_SIZE)), 12)
		_label.font_size = maxi(int(round(max_font * factor)), 10)


func get_text() -> String:
	return _text


func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left = maxf(_flash_left - delta, 0.0)
		if _flash_left <= 0.0 and not is_grabbed():
			_pressed = false
			_refresh()


func _exit_tree() -> void:
	_grabbed_by = null
	_pressed = false
	_flash_left = 0.0


func _refresh() -> void:
	if _background == null:
		return
	var color := UIStyle.COLOR_BUTTON
	var text_color := UIStyle.COLOR_TEXT
	if not enabled:
		color = UIStyle.COLOR_BUTTON_DISABLED
		text_color = UIStyle.COLOR_TEXT_DIM
	elif _pressed or _flash_left > 0.0:
		color = UIStyle.COLOR_BUTTON_ACTIVE
		text_color = UIStyle.COLOR_TEXT_ON_ACTIVE
	elif selected:
		color = UIStyle.COLOR_FILL
		text_color = UIStyle.COLOR_TEXT_ON_ACTIVE
	elif _hovered:
		color = UIStyle.COLOR_BUTTON_HOVER
	_background.material_override = UIStyle.quad_material(color, 2)
	if _label != null:
		_label.modulate = text_color


func uses_select_input() -> bool:
	return true


func can_grab(point: Vector3) -> bool:
	if not enabled or is_grabbed():
		return false
	var local := to_local(point)
	return absf(local.z) <= SURFACE_TOLERANCE \
			and absf(local.x) <= size.x * 0.5 + GRAB_PADDING \
			and absf(local.y) <= size.y * 0.5 + GRAB_PADDING


func get_grab_priority() -> int:
	return 40


func get_grab_distance(point: Vector3) -> float:
	var local := to_local(point)
	var outside := Vector2(
		maxf(absf(local.x) - size.x * 0.5, 0.0),
		maxf(absf(local.y) - size.y * 0.5, 0.0))
	return outside.length() + absf(local.z)


func get_grab_radius() -> float:
	return Vector2(size.x * 0.5 + GRAB_PADDING, size.y * 0.5 + GRAB_PADDING).length()


func ray_hit(origin: Vector3, direction: Vector3, max_distance: float) -> float:
	if not enabled or is_grabbed():
		return INF
	var hit := XRPointerRay.ray_plane_local(self, origin, direction)
	if hit.is_empty():
		return INF
	if float(hit["distance"]) > max_distance:
		return INF
	if absf(float(hit["x"])) > size.x * 0.5 + GRAB_PADDING:
		return INF
	if absf(float(hit["y"])) > size.y * 0.5 + GRAB_PADDING:
		return INF
	return float(hit["distance"])


func is_grabbed() -> bool:
	return _grabbed_by != null


func set_hover(hovered: bool) -> void:
	if _hovered == hovered:
		return
	_hovered = hovered
	_refresh()


func begin_grab(interactor: XRInteractor) -> void:
	if not enabled:
		return
	_grabbed_by = interactor
	_pressed = true
	_flash_left = PRESS_FLASH_SEC
	_refresh()
	pressed.emit(self)


func drag_grab(_interactor: XRInteractor) -> void:
	pass


func end_grab(_interactor: XRInteractor) -> void:
	_grabbed_by = null
	if _flash_left <= 0.0:
		_pressed = false
	_refresh()
