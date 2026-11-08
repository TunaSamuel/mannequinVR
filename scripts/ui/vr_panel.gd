class_name VRPanel
extends Node3D
## World-space panel: background, draggable header, title and status line.
## Content is rebuilt by subclasses into `content_root`.

const PANEL_SIZE := Vector2(0.58, 0.47)
const CONTENT_LEFT := -0.255
const CONTENT_RIGHT := 0.255

var _background: MeshInstance3D
var _title_label: Label3D
var _status_label: Label3D
var _drag_handle: UIDragHandle
var _content: Node3D
## When true the panel yaws to face the headset. Disabled while the user is
## dragging it so placement stays intentional.
var auto_face := true
const FACE_SPEED := 8.0


func setup() -> void:
	_background = UIStyle.quad(PANEL_SIZE, UIStyle.COLOR_PANEL, 0)
	add_child(_background)

	_drag_handle = UIDragHandle.new()
	add_child(_drag_handle)
	_drag_handle.position = Vector3(0, PANEL_SIZE.y * 0.5 - 0.026, 0.001)
	_drag_handle.target = self
	_drag_handle.setup("drag to move", Vector2(PANEL_SIZE.x - 0.04, 0.026), 0.013)

	_title_label = UIStyle.make_label("", 0.024, UIStyle.COLOR_TEXT)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title_label.width = (PANEL_SIZE.x - 0.04) / UIStyle.FONT_PIXEL_SIZE
	_title_label.position = Vector3(0, PANEL_SIZE.y * 0.5 - 0.062, 0.0025)
	add_child(_title_label)

	_status_label = UIStyle.make_label("", 0.015, UIStyle.COLOR_TEXT_DIM)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_status_label.width = (PANEL_SIZE.x - 0.04) / UIStyle.FONT_PIXEL_SIZE
	_status_label.position = Vector3(0, -PANEL_SIZE.y * 0.5 + 0.018, 0.0025)
	add_child(_status_label)

	_content = Node3D.new()
	_content.name = "Content"
	add_child(_content)

	set_title("VR CHARACTER POSER")
	set_status("Starting up...")


func content_root() -> Node3D:
	return _content


func set_title(text: String) -> void:
	if _title_label != null:
		_title_label.text = text


func set_status(text: String, is_error: bool = false) -> void:
	if _status_label == null:
		return
	var shortened := text
	if shortened.length() > 74:
		shortened = shortened.substr(0, 71) + "..."
	_status_label.text = shortened
	_status_label.modulate = Color(1.0, 0.55, 0.45) if is_error else UIStyle.COLOR_TEXT_DIM


func clear_content() -> void:
	if _content == null:
		return
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()


func add_label(text: String, local_position: Vector3, height: float,
		color: Color = UIStyle.COLOR_TEXT,
		alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label3D:
	var label := UIStyle.make_label(text, height, color)
	label.horizontal_alignment = alignment
	label.width = (PANEL_SIZE.x - 0.05) / UIStyle.FONT_PIXEL_SIZE
	label.position = local_position + Vector3(0, 0, 0.0025)
	_content.add_child(label)
	return label


func add_button(text: String, local_position: Vector3, button_size: Vector2,
		height: float = 0.019) -> UIButton3D:
	var button := UIButton3D.new()
	_content.add_child(button)
	button.position = local_position
	button.setup(text, button_size, height)
	return button


func add_slider(title: String, local_position: Vector3, track_length: float,
		height: float = 0.014) -> UISlider3D:
	var slider := UISlider3D.new()
	_content.add_child(slider)
	slider.position = local_position
	slider.setup(title, track_length, height)
	return slider


func set_auto_face(enabled: bool) -> void:
	auto_face = enabled


func _process(delta: float) -> void:
	if not auto_face:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var to_cam := cam.global_position - global_position
	to_cam.y = 0.0
	if to_cam.length_squared() < 0.0001:
		return
	# Panel faces the user: look along -to_cam so the front points toward the camera.
	var desired := Basis.looking_at(-to_cam.normalized(), Vector3.UP)
	var current := global_transform.basis.orthonormalized()
	var blended := current.slerp(desired, 1.0 - exp(-FACE_SPEED * delta))
	global_transform = Transform3D(blended, global_position)
