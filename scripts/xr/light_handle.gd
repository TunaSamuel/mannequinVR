class_name LightHandle
extends Node3D
## Grabbable marker for the scene fill OmniLight3D. Grip-drag to move the light;
## power / range / color are edited from the Help tab.

const NORMAL_COLOR := Color(1.0, 0.92, 0.55, 0.75)
const HOVER_COLOR := Color(1.0, 0.98, 0.70, 0.95)
const ACTIVE_COLOR := Color(1.0, 0.75, 0.25, 1.0)

var light: OmniLight3D
var grab_radius := 0.08

var _mesh: MeshInstance3D
var _label: Label3D
var _hovered := false
var _grabbed_by: XRInteractor
var _offset_local := Vector3.ZERO
var _mat_normal: StandardMaterial3D
var _mat_hover: StandardMaterial3D
var _mat_active: StandardMaterial3D


func setup(omni: OmniLight3D) -> void:
	light = omni
	_build_visuals()
	add_to_group("grab_target")
	if light != null:
		global_position = light.global_position


func _build_visuals() -> void:
	_mat_normal = _make_mat(NORMAL_COLOR)
	_mat_hover = _make_mat(HOVER_COLOR)
	_mat_active = _make_mat(ACTIVE_COLOR)

	var sphere := SphereMesh.new()
	sphere.radius = 0.035
	sphere.height = 0.07
	sphere.radial_segments = 12
	sphere.rings = 6
	sphere.material = _mat_normal

	_mesh = MeshInstance3D.new()
	_mesh.mesh = sphere
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)

	_label = Label3D.new()
	_label.text = "Light"
	_label.font_size = 26
	_label.pixel_size = 0.0012
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0.0, 0.055, 0.0)
	_label.modulate = Color(1.0, 0.95, 0.7, 1.0)
	_label.outline_modulate = Color(0.05, 0.05, 0.08, 0.9)
	_label.outline_size = 5
	_label.no_depth_test = true
	_label.render_priority = 4
	_label.visible = false
	add_child(_label)


func _make_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.disable_receive_shadows = true
	return m


func _exit_tree() -> void:
	_grabbed_by = null


func can_grab(point: Vector3) -> bool:
	if light == null or is_grabbed():
		return false
	return global_position.distance_to(point) <= grab_radius


func ray_hit(origin: Vector3, direction: Vector3, max_distance: float) -> float:
	if light == null or is_grabbed():
		return INF
	return XRPointerRay.ray_sphere(origin, direction, global_position, grab_radius, max_distance)


func get_grab_priority() -> int:
	return 15


func get_grab_distance(point: Vector3) -> float:
	return global_position.distance_to(point)


func set_hover(hovered: bool) -> void:
	_hovered = hovered
	_refresh_visual()


func is_grabbed() -> bool:
	return _grabbed_by != null


func begin_grab(interactor: XRInteractor) -> void:
	if light == null:
		return
	_grabbed_by = interactor
	_offset_local = interactor.get_grab_point() - global_position
	_refresh_visual()


func drag_grab(interactor: XRInteractor) -> void:
	if _grabbed_by != interactor or light == null:
		return
	global_position = interactor.get_grab_point() - _offset_local
	light.global_position = global_position


func end_grab(_interactor: XRInteractor) -> void:
	_grabbed_by = null
	_refresh_visual()


func _refresh_visual() -> void:
	if _mesh == null:
		return
	if is_grabbed():
		_mesh.material_override = _mat_active
	elif _hovered:
		_mesh.material_override = _mat_hover
	else:
		_mesh.material_override = _mat_normal
	if _label != null:
		_label.visible = _hovered or is_grabbed()


func sync_from_light() -> void:
	if light != null:
		global_position = light.global_position
