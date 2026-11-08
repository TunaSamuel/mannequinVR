extends Node3D
## Application root: XR bring-up, passthrough, wiring and auto-loading the last
## character. All behaviour lives in the smaller systems below.

const CHARACTER_DISTANCE := 1.15
const PANEL_LOCAL_OFFSET := Vector3(-0.30, 1.28, -0.55)
const PANEL_FALLBACK_POSITION := Vector3(-0.30, 1.30, -0.95)
## Left stick moves the player (XR origin). Right stick X turns only.
## Model height is the Floor slider (or grip-grab the body).
const MOVE_SPEED := 1.4
const TURN_SPEED := 1.6
const STICK_DEADZONE := 0.18

var library := ModelLibrary.new()

@onready var xr_origin: XROrigin3D = $XROrigin3D
@onready var camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var rig: CharacterRig = $CharacterRoot
@onready var interaction: InteractionManager = $InteractionManager
@onready var panel: PosePanel = $PosePanel
@onready var floor_ring: MeshInstance3D = $FloorRing

var _openxr: OpenXRInterface
var _xr_active := false


func _ready() -> void:
	_openxr = XRServer.find_interface("OpenXR") as OpenXRInterface
	_xr_active = _openxr != null and _openxr.is_initialized()

	_setup_passthrough()
	_setup_environment()
	_setup_floor_ring()
	_register_interactors(xr_origin)

	library.ensure_directories()
	panel.configure(library, rig)

	rig.global_position = Vector3(0.0, 0.0, -CHARACTER_DISTANCE)
	_place_panel()
	_auto_load_recent()

	if not _xr_active:
		_show_diagnostics()
	_log_startup()


func _process(delta: float) -> void:
	_update_locomotion(delta)
	if floor_ring != null:
		floor_ring.global_position = Vector3(rig.global_position.x, 0.002, rig.global_position.z)


func _update_locomotion(delta: float) -> void:
	if not _xr_active or xr_origin == null or camera == null:
		return
	var left := Vector2.ZERO
	var right := Vector2.ZERO
	for interactor in interaction.interactors():
		if interactor is ControllerInteractor:
			var c := interactor as ControllerInteractor
			var axis := _apply_deadzone(c.get_primary_axis())
			if c.is_left_hand():
				left = axis
			else:
				right = axis

	# Left stick: walk the player relative to head yaw (keep Y fixed).
	if left.length_squared() > 0.0:
		var forward := -camera.global_transform.basis.z
		forward.y = 0.0
		if forward.length_squared() > 0.0001:
			forward = forward.normalized()
		else:
			forward = Vector3.FORWARD
		var right_dir := camera.global_transform.basis.x
		right_dir.y = 0.0
		if right_dir.length_squared() > 0.0001:
			right_dir = right_dir.normalized()
		else:
			right_dir = Vector3.RIGHT
		var move := (right_dir * left.x + forward * left.y) * MOVE_SPEED * delta
		xr_origin.global_position += move

	# Right stick X only: smooth turn. Ignore Y so slight vertical bias on the
	# stick cannot spin the player. Model height is the Floor slider / grip-grab.
	if absf(right.x) > 0.0:
		xr_origin.rotate_y(-right.x * TURN_SPEED * delta)


func _apply_deadzone(v: Vector2) -> Vector2:
	var length := v.length()
	if length < STICK_DEADZONE:
		return Vector2.ZERO
	# Rescale past the deadzone so small intentional inputs still reach full range.
	var scaled := v.normalized() * ((length - STICK_DEADZONE) / maxf(1.0 - STICK_DEADZONE, 0.001))
	return scaled.limit_length(1.0)


func _setup_passthrough() -> void:
	if not _xr_active:
		return
	# The OpenXR environment blend mode is set to alpha blend in project
	# settings; the viewport must also be transparent for passthrough to show.
	var viewport := get_viewport()
	viewport.transparent_bg = true
	# Without this the OpenXR compositor gets nothing to present and the
	# engine warns "No viewport was marked with use_xr, there is no rendered
	# output". Marking the root viewport is the real fix, not a hack.
	viewport.use_xr = true
	if camera != null:
		camera.current = true


## Passthrough means there is no sky to light the character, and an unlit model
## in a real room is nearly invisible. Ambient light plus one shadowless key
## light keeps characters readable without costing much on mobile.
func _setup_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.78, 0.90)
	environment.ambient_light_energy = 0.65
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR

	var world_environment := WorldEnvironment.new()
	world_environment.name = "Lighting"
	world_environment.environment = environment
	add_child(world_environment)

	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	key.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	key.light_energy = 1.1
	key.light_color = Color(1.0, 0.97, 0.92)
	# Shadows are expensive on mobile and look wrong floating in a real room.
	key.shadow_enabled = false
	add_child(key)

	var fill := OmniLight3D.new()
	fill.name = "FillLight"
	fill.position = Vector3(0.9, 1.6, 0.7)
	fill.omni_range = 4.5
	fill.light_energy = 1.6
	fill.shadow_enabled = false
	add_child(fill)


func _register_interactors(node: Node) -> void:
	for child in node.get_children():
		if child is XRInteractor:
			interaction.register_interactor(child as XRInteractor)
		_register_interactors(child)


func _place_panel() -> void:
	var basis := Basis(Vector3.RIGHT, deg_to_rad(-16.0)) * Basis(Vector3.UP, deg_to_rad(10.0))
	var origin := xr_origin.global_transform.origin
	panel.global_transform = Transform3D(basis, origin + PANEL_LOCAL_OFFSET)
	if not _xr_active:
		panel.global_transform = Transform3D(basis, PANEL_FALLBACK_POSITION)


func _auto_load_recent() -> void:
	var recents := library.recents()
	if recents.is_empty():
		panel.set_status("Copy .glb characters into the models folder, then pick one.")
		return
	var result := rig.load_model(recents[0])
	if result.ok:
		panel.set_status("Loaded %s. Pinch or grip a joint to pose." % rig.model_name)
	else:
		panel.set_status(result.error, true)
	panel.refresh()


func _setup_floor_ring() -> void:
	if floor_ring == null:
		return
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.5
	mesh.height = 0.004
	mesh.radial_segments = 48
	mesh.rings = 1
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.31, 0.82, 0.80, 0.12)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.disable_receive_shadows = true
	mesh.material = material
	floor_ring.mesh = mesh
	floor_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _log_startup() -> void:
	print("[VR Poser] OpenXR active: ", _xr_active)
	if _openxr != null:
		print("[VR Poser] OpenXR initialized: ", _openxr.is_initialized(),
				", session state: ", _openxr.get_session_state())
		print("[VR Poser] hand tracking supported: ", _openxr.is_hand_tracking_supported())
	print("[VR Poser] model folders: ", library.directories())
	print("[VR Poser] recent models: ", library.recents())


## Shown when no OpenXR runtime is running (editor / desktop). This is a
## developer diagnostic, not a desktop posing mode.
func _show_diagnostics() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Diagnostics"
	add_child(layer)

	var background := ColorRect.new()
	background.color = Color(0.04, 0.05, 0.07, 1.0)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(background)

	var label := Label.new()
	label.text = "\n".join([
		"VR Character Poser - no OpenXR runtime detected",
		"",
		"This build targets Meta Quest 3 standalone (OpenXR).",
		"Start a PC VR runtime or install the APK on the headset to see the VR view.",
		"",
		"Model folders:",
		"\n".join(library.directories()),
		"",
		"Recent: %s" % (", ".join(library.recents()) if not library.recents().is_empty() else "(none)"),
	])
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.offset_left = 48
	label.offset_top = 48
	label.offset_right = -48
	label.offset_bottom = -48
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 22)
	layer.add_child(label)
