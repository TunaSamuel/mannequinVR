extends Node3D
## Headless self-test for the non-VR systems.
##
##   godot --headless --path . res://tests/selftest.tscn
##
## Exits 0 when every check passes, 1 otherwise. It builds its own character
## rig, so it needs no external model files (though it does round-trip a GLB
## through the real runtime loader).

var _passed := 0
var _failed := 0
var _current := ""

const TOLERANCE := 0.002


func _ready() -> void:
	await _run()
	print("")
	if _failed == 0:
		print("SELFTEST PASSED (%d checks)" % _passed)
	else:
		print("SELFTEST FAILED (%d passed, %d failed)" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
		print("  ok   ", message)
	else:
		_failed += 1
		print("  FAIL ", message)


func _section(title: String) -> void:
	_current = title
	print("\n[", title, "]")


func _run() -> void:
	await _test_loader_and_glb_roundtrip()
	await _test_install_and_analyse()
	await _test_bone_handle_rotation()
	await _test_reset_pose()
	await _test_blend_shapes()
	await _test_pose_presets()
	await _test_model_library()
	await _test_interaction_routing()
	await _test_pointer_ray()
	await _test_stale_grab_target()
	await _test_scale_controls()
	await _test_model_scan_report()
	await _test_two_handed_scale()
	await _test_model_without_skeleton()
	await _test_panel_construction()
	await _test_scene_wiring()
	_cleanup()


# --- Fixtures --------------------------------------------------------------

var bone_definitions := [
	{"name": "Hips", "parent": -1, "offset": Vector3(0, 1.0, 0)},
	{"name": "Spine", "parent": 0, "offset": Vector3(0, 0.35, 0)},
	{"name": "Head", "parent": 1, "offset": Vector3(0, 0.45, 0)},
	{"name": "LeftUpperArm", "parent": 1, "offset": Vector3(0.18, 0.30, 0)},
	{"name": "LeftLowerArm", "parent": 3, "offset": Vector3(0.28, 0, 0)},
	{"name": "LeftHand", "parent": 4, "offset": Vector3(0.25, 0, 0)},
	{"name": "RightUpperArm", "parent": 1, "offset": Vector3(-0.18, 0.30, 0)},
	{"name": "RightLowerArm", "parent": 6, "offset": Vector3(-0.28, 0, 0)},
	{"name": "LeftUpperLeg", "parent": 0, "offset": Vector3(0.10, -0.05, 0)},
	{"name": "LeftLowerLeg", "parent": 8, "offset": Vector3(0, -0.45, 0)},
	{"name": "LeftFoot", "parent": 9, "offset": Vector3(0, -0.42, 0)},
	{"name": "RightUpperLeg", "parent": 0, "offset": Vector3(-0.10, -0.05, 0)},
	{"name": "RightLowerLeg", "parent": 11, "offset": Vector3(0, -0.45, 0)},
	{"name": "RightFoot", "parent": 12, "offset": Vector3(0, -0.42, 0)},
]


func _build_skeleton() -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	for definition in bone_definitions:
		var index := skeleton.add_bone(String(definition["name"]))
		var parent: int = definition["parent"]
		if parent >= 0:
			skeleton.set_bone_parent(index, parent)
		skeleton.set_bone_rest(index, Transform3D(Basis(), definition["offset"]))
	return skeleton


## A skinned quad with two blend shapes, tall enough not to be auto-rescaled.
func _build_character() -> Node3D:
	var root := Node3D.new()
	root.name = "TestCharacter"
	var skeleton := _build_skeleton()
	root.add_child(skeleton)

	var vertices := PackedVector3Array([
		Vector3(-0.15, 0.2, 0), Vector3(0.15, 0.2, 0),
		Vector3(0.15, 1.8, 0), Vector3(-0.15, 1.8, 0),
	])
	var normals := PackedVector3Array([
		Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1),
	])
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for vertex in 4:
		var bone := 0 if vertex < 2 else 1
		bones.append(bone)
		bones.append(0)
		bones.append(0)
		bones.append(0)
		weights.append(1.0)
		weights.append(0.0)
		weights.append(0.0)
		weights.append(0.0)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])

	var smile := []
	smile.resize(Mesh.ARRAY_MAX)
	smile[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-0.2, 0.2, 0), Vector3(0.2, 0.2, 0),
		Vector3(0.2, 1.85, 0), Vector3(-0.2, 1.85, 0),
	])
	smile[Mesh.ARRAY_NORMAL] = normals

	var blink := []
	blink.resize(Mesh.ARRAY_MAX)
	blink[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-0.15, 0.2, 0.05), Vector3(0.15, 0.2, 0.05),
		Vector3(0.15, 1.75, 0.05), Vector3(-0.15, 1.75, 0.05),
	])
	blink[Mesh.ARRAY_NORMAL] = normals

	var mesh := ArrayMesh.new()
	mesh.add_blend_shape("Smile")
	mesh.add_blend_shape("Blink")
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [smile, blink])

	var instance := MeshInstance3D.new()
	instance.name = "Body"
	instance.mesh = mesh
	instance.skin = skeleton.create_skin_from_rest_transforms()
	root.add_child(instance)
	instance.skeleton = instance.get_path_to(skeleton)
	return root


func _pose_close(a: Transform3D, b: Transform3D) -> bool:
	if a.origin.distance_to(b.origin) > TOLERANCE:
		return false
	return a.basis.get_rotation_quaternion().angle_to(b.basis.get_rotation_quaternion()) < 0.02


# --- Tests -----------------------------------------------------------------

func _test_loader_and_glb_roundtrip() -> void:
	_section("glTF runtime loader")
	var fixture := _build_character()
	add_child(fixture)

	var document := GLTFDocument.new()
	var state := GLTFState.new()
	_check(document.append_from_scene(fixture, state) == OK, "fixture exported to glTF state")
	var path := "user://selftest_character.glb"
	_check(document.write_to_filesystem(state, path) == OK, "fixture written as GLB")
	fixture.queue_free()
	await get_tree().process_frame

	var result := ModelLoader.load_from_path(path)
	_check(result.ok, "GLB loads at runtime: %s" % result.error)
	if result.ok:
		_check(int(result.stats["skeletons"]) >= 1, "GLB kept its skeleton")
		_check(int(result.stats["mesh_instances"]) >= 1, "GLB kept its mesh")
		_check(int(result.stats["blend_shapes"]) >= 2, "GLB kept its blend shapes")
		_check(float(result.stats["height"]) > 0.5, "bounds were measured (height %.2f)" % float(result.stats["height"]))
		result.scene.free()

	var missing := ModelLoader.load_from_path("user://does_not_exist.glb")
	_check(not missing.ok and missing.error.contains("not found"), "missing file reports an error")
	var fbx := ModelLoader.load_from_path("user://character.fbx")
	_check(not fbx.ok and fbx.error.contains("FBX"), "FBX is rejected with conversion advice")


func _test_install_and_analyse() -> void:
	_section("character rig install")
	var rig := CharacterRig.new()
	add_child(rig)
	var info := rig.install_model(_build_character(), "test://fixture", "Fixture")
	_check(rig.has_model(), "model is installed")
	_check(rig.posers.size() == 1, "one skeleton poser created")
	_check(rig.blend_shapes.count() == 2, "two blend shapes found (%d)" % rig.blend_shapes.count())
	_check(int(info["handles"]) > 0, "major-bone handles generated (%d)" % int(info["handles"]))
	_check(rig.world_bounds().size.y > 1.0, "world bounds computed")
	rig.queue_free()
	await get_tree().process_frame


func _test_bone_handle_rotation() -> void:
	_section("bone handle rotation")
	var rig := await _spawn_rig()
	var poser: SkeletonPoser = rig.posers[0]
	var bone := poser.skeleton.find_bone("LeftUpperArm")
	var handle := poser.handle_for_bone(bone)
	_check(handle != null, "LeftUpperArm has a handle")
	if handle == null:
		rig.queue_free()
		return

	var child_bone := poser.skeleton.find_bone("LeftLowerArm")
	var child_before := poser.skeleton.get_bone_global_pose(child_bone).origin
	var rest := poser.skeleton.get_bone_pose(bone)

	var hand := FakeInteractor.new()
	add_child(hand)
	hand.point = handle.global_position
	hand.basis_override = Basis.IDENTITY
	handle.begin_grab(hand)
	hand.basis_override = Basis(Vector3.UP, deg_to_rad(55.0))
	handle.drag_grab(hand)
	handle.end_grab(hand)

	var posed := poser.skeleton.get_bone_pose(bone)
	var angle := rest.basis.get_rotation_quaternion().angle_to(
			posed.basis.get_rotation_quaternion())
	_check(rad_to_deg(angle) > 30.0, "bone rotated with the hand (%.1f deg)" % rad_to_deg(angle))
	var child_after := poser.skeleton.get_bone_global_pose(child_bone).origin
	_check(child_before.distance_to(child_after) > 0.02,
			"child joint followed the parent (moved %.3f m)" % child_before.distance_to(child_after))

	# Handle position must stay glued to the joint.
	handle.sync_transform()
	var joint_world: Vector3 = poser.skeleton.global_transform * poser.skeleton.get_bone_global_pose(bone).origin
	_check(handle.global_position.distance_to(joint_world) < 0.001, "handle stays on its joint")

	hand.queue_free()
	rig.queue_free()
	await get_tree().process_frame


func _test_reset_pose() -> void:
	_section("reset pose")
	var rig := await _spawn_rig()
	var poser: SkeletonPoser = rig.posers[0]
	var skeleton := poser.skeleton
	var bone := skeleton.find_bone("Spine")
	var rest := skeleton.get_bone_rest(bone)
	skeleton.set_bone_pose_rotation(bone, Quaternion(Vector3(1, 0, 0), deg_to_rad(40.0)))
	_check(not _pose_close(skeleton.get_bone_pose(bone), rest), "bone was posed")
	rig.reset_pose()
	_check(_pose_close(skeleton.get_bone_pose(bone), rest), "reset restores the rest pose")
	rig.queue_free()
	await get_tree().process_frame


func _test_blend_shapes() -> void:
	_section("blend shapes")
	var rig := await _spawn_rig()
	var shapes := rig.blend_shapes
	var entry: Dictionary = shapes.entries[0]
	var instance: MeshInstance3D = entry["node"]
	shapes.set_value(0, 0.75)
	_check(absf(instance.get_blend_shape_value(int(entry["index"])) - 0.75) < 0.001,
			"weight applied to the mesh")
	_check(shapes.display_name(0).begins_with(String(entry["name"])), "display name available")
	var snapshot := shapes.capture()
	shapes.reset_all()
	_check(absf(instance.get_blend_shape_value(int(entry["index"]))) < 0.001, "reset clears weights")
	shapes.apply(snapshot)
	_check(absf(instance.get_blend_shape_value(int(entry["index"])) - 0.75) < 0.001,
			"weights restored from a snapshot")
	rig.queue_free()
	await get_tree().process_frame


func _test_pose_presets() -> void:
	_section("pose presets")
	var rig := await _spawn_rig()
	var poser: SkeletonPoser = rig.posers[0]
	var skeleton := poser.skeleton

	var bone := skeleton.find_bone("LeftLowerArm")
	skeleton.set_bone_pose_rotation(bone, Quaternion(Vector3(0, 0, 1), deg_to_rad(35.0)))
	rig.blend_shapes.set_value(1, 0.6)
	rig.position = Vector3(0.4, 0.1, -1.2)
	rig.scale = Vector3.ONE * 1.1

	var document := rig.capture_pose()
	_check(int(document.get("version", 0)) == PoseStore.FORMAT_VERSION, "pose document is versioned")
	var baked := skeleton.get_bone_pose(bone)

	rig.reset_pose()
	rig.blend_shapes.set_value(1, 0.0)
	rig.position = Vector3.ZERO
	rig.scale = Vector3.ONE

	var summary := rig.apply_pose(document)
	_check(_pose_close(skeleton.get_bone_pose(bone), baked), "bone pose restored from the document")
	_check(absf(rig.blend_shapes.get_value(1) - 0.6) < 0.001, "blend shape restored from the document")
	_check(absf(rig.position.x - 0.4) < 0.01, "character transform restored")
	_check(int(summary["bones"]) > 0, "summary reports restored bones")

	var path := PoseStore.save(document)
	_check(not path.is_empty() and FileAccess.file_exists(path), "pose written to user://poses")
	var reloaded := PoseStore.read(path)
	_check(int(reloaded.get("version", 0)) == PoseStore.FORMAT_VERSION, "pose file reads back")
	var listed := PoseStore.list_poses()
	var found := false
	for entry in listed:
		if String(entry["path"]) == path:
			found = true
	_check(found, "pose appears in the pose library")
	PoseStore.delete(path)

	rig.queue_free()
	await get_tree().process_frame


func _test_model_library() -> void:
	_section("model library")
	var directory := "user://selftest_models"
	DirAccess.make_dir_recursive_absolute(directory)
	var source := "user://selftest_character.glb"
	var target := directory.path_join("Selftest Character.glb")
	if FileAccess.file_exists(source):
		DirAccess.copy_absolute(source, target)
	OS.set_environment("VR_POSER_MODELS", ProjectSettings.globalize_path(directory))
	var library := ModelLibrary.new()
	var entries := library.scan()
	_check(entries.size() >= 1, "model folder scanned (%d found)" % entries.size())
	if not entries.is_empty():
		_check(String(entries[0]["name"]).begins_with("Selftest"), "entry name is derived from the file")
		library.mark_recent(String(entries[0]["path"]))
		_check(library.recents().has(String(entries[0]["path"])), "model remembered as recent")
		var loaded := ModelLoader.load_from_path(String(entries[0]["path"]))
		_check(loaded.ok, "scanned model loads")
		if loaded.ok:
			loaded.scene.free()
	OS.set_environment("VR_POSER_MODELS", "")
	DirAccess.remove_absolute(target)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
	if FileAccess.file_exists(ModelLibrary.RECENTS_PATH):
		DirAccess.remove_absolute(ModelLibrary.RECENTS_PATH)


func _test_interaction_routing() -> void:
	_section("grab routing")
	var rig := await _spawn_rig()
	var manager := InteractionManager.new()
	add_child(manager)
	var hand := FakeInteractor.new()
	add_child(hand)
	manager.register_interactor(hand)

	var poser: SkeletonPoser = rig.posers[0]
	var bone := poser.skeleton.find_bone("Head")
	var handle := poser.handle_for_bone(bone)
	_check(handle != null, "head handle exists")
	if handle == null:
		rig.queue_free()
		return

	hand.point = handle.global_position
	hand.grip = 1.0
	manager._process(0.016)
	_check(handle.is_grabbed(), "grip started a grab on the nearest handle")

	hand.basis_override = Basis(Vector3.UP, deg_to_rad(30.0))
	manager._process(0.016)
	var rest := poser.skeleton.get_bone_rest(bone)
	_check(not _pose_close(poser.skeleton.get_bone_pose(bone), rest), "dragging the handle posed the bone")

	hand.grip = 0.0
	manager._process(0.016)
	_check(not handle.is_grabbed(), "releasing grip drops the handle")

	rig.queue_free()
	manager.queue_free()
	hand.queue_free()
	await get_tree().process_frame


func _test_two_handed_scale() -> void:
	_section("two-handed character transform")
	var rig := await _spawn_rig()
	rig.reset_pose()
	# Bone handles outrank the body, so hide them to grab the character itself.
	for poser in rig.posers:
		poser.set_filter(SkeletonPoser.BoneFilter.NONE)
	await get_tree().process_frame
	var manager := InteractionManager.new()
	add_child(manager)
	var left := FakeInteractor.new()
	var right := FakeInteractor.new()
	add_child(left)
	add_child(right)
	manager.register_interactor(left)
	manager.register_interactor(right)

	var center := rig.world_bounds().get_center()
	left.point = center + Vector3(-0.02, 0, 0)
	right.point = center + Vector3(0.02, 0, 0)
	left.grip = 1.0
	right.grip = 1.0
	manager._process(0.016)
	manager._process(0.016)
	var start_scale := rig.scale.x
	_check(rig.is_grabbed(), "character grabbed")

	left.point = center + Vector3(-0.06, 0, 0)
	right.point = center + Vector3(0.06, 0, 0)
	manager._process(0.016)
	_check(rig.scale.x > start_scale * 1.5, "spreading hands scales the character up (%.2f -> %.2f)" % [start_scale, rig.scale.x])

	var moved_center := rig.world_bounds().get_center()
	left.point += Vector3(0.25, 0.1, 0)
	right.point += Vector3(0.25, 0.1, 0)
	manager._process(0.016)
	_check(rig.world_bounds().get_center().distance_to(moved_center) > 0.1, "moving both hands moves the character")

	left.grip = 0.0
	right.grip = 0.0
	manager._process(0.016)
	_check(not rig.is_grabbed(), "character released")

	rig.queue_free()
	manager.queue_free()
	left.queue_free()
	right.queue_free()
	await get_tree().process_frame


func _test_model_without_skeleton() -> void:
	_section("validation warnings")
	var root := Node3D.new()
	root.name = "Prop"
	var instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.5, 0.5)
	instance.mesh = box
	root.add_child(instance)
	var rig := CharacterRig.new()
	add_child(rig)
	rig.install_model(root, "test://prop", "Prop")
	_check(rig.posers.is_empty(), "no poser for a skeleton-less model")
	_check(rig.blend_shapes.count() == 0, "no blend shapes reported")
	var warnings := rig.get_info()["warnings"] as PackedStringArray
	_check(not warnings.is_empty() and warnings[0].contains("skeleton"), "missing skeleton is warned about")
	rig.queue_free()
	await get_tree().process_frame


func _test_panel_construction() -> void:
	_section("panel construction")
	var library := ModelLibrary.new()
	var rig := await _spawn_rig()
	var panel := PosePanel.new()
	add_child(panel)
	panel.position = Vector3(0, 1.3, -0.6)
	panel.configure(library, rig)
	await get_tree().process_frame
	_check(panel.content_root().get_child_count() > 0, "models tab builds content")

	for tab in 3:
		panel._on_tab_pressed(null, tab)
		await get_tree().process_frame
		_check(panel.content_root().get_child_count() > 0, "tab %d builds content" % tab)

	_check(panel.library == library and panel.rig == rig, "panel is wired to the library and rig")

	# Panel drag bar must move the panel when grabbed.
	var bar: UIButton3D = null
	for child in panel.get_children():
		if child is UIDragHandle:
			bar = child
	_check(bar != null, "panel has a drag handle")
	if bar != null:
		var hand := FakeInteractor.new()
		add_child(hand)
		var before := panel.global_position
		hand.point = bar.global_position
		bar.begin_grab(hand)
		hand.point += Vector3(0.1, 0, 0)
		bar.drag_grab(hand)
		bar.end_grab(hand)
		_check(panel.global_position.distance_to(before) > 0.05, "dragging the bar moves the panel")
		hand.queue_free()

	panel.queue_free()
	rig.queue_free()
	await get_tree().process_frame


func _test_pointer_ray() -> void:
	_section("laser pointer")
	var button := UIButton3D.new()
	add_child(button)
	button.position = Vector3(0, 1.2, -0.6)
	button.setup("Tap", Vector2(0.2, 0.05))
	await get_tree().process_frame

	var origin := Vector3(0, 1.2, 0.0)
	var hit := XRPointerRay.cast(origin, Vector3.FORWARD, 1.7, [button])
	_check(not hit.is_empty(), "ray finds a panel button in front of it")
	if not hit.is_empty():
		var distance := float(hit["distance"])
		_check(distance > 0.5 and distance < 0.7, "hit distance is measured along the ray (%.2f m)" % distance)
		_check(button.can_grab(hit["point"] as Vector3), "the pointer point is a valid grab point")
	_check(XRPointerRay.cast(origin, Vector3.RIGHT, 1.7, [button]).is_empty(),
			"aiming away misses the button")

	# Drive the real pointer node once so drawing, colours and visibility are
	# exercised, not just the maths.
	var pointer := XRPointerRay.new()
	add_child(pointer)
	await get_tree().process_frame
	pointer.update_ray(origin, Vector3.FORWARD, [button])
	_check(pointer.visible and pointer.has_hit, "pointer ray becomes visible when it hits")
	_check(pointer.get_node_or_null("Line") != null, "pointer draws a laser line")
	_check(pointer.get_node_or_null("Cursor") != null and pointer.get_node("Cursor").visible,
			"pointer shows a cursor on the hit point")
	pointer.hide_ray()
	_check(not pointer.visible and not pointer.has_hit, "pointer hides itself when not tracking")
	pointer.queue_free()
	button.queue_free()

	var rig := await _spawn_rig()
	var poser: SkeletonPoser = rig.posers[0]
	var handle := poser.handle_for_bone(poser.skeleton.find_bone("Head"))
	_check(handle != null, "head handle exists for pointer tests")
	if handle != null:
		var handle_origin := handle.global_position + Vector3(0, 0, 0.4)
		var sphere_hit := XRPointerRay.ray_sphere(handle_origin, Vector3.FORWARD,
				handle.global_position, handle.get_grab_radius(), 1.7)
		_check(sphere_hit != INF, "ray hits the joint sphere")
		handle.set_hover(true)
		_check(handle.get_highlight() == BoneHandle.Highlight.HOVER, "hovering a joint highlights it")
		handle.set_hover(false)
		_check(handle.get_highlight() == BoneHandle.Highlight.NONE, "leaving the joint clears the highlight")

	_check(XRPointerRay.ray_aabb(Vector3(0, 0, 2), Vector3.FORWARD,
			AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2)), 5.0) < 1.5, "ray reaches the character box")
	_check(XRPointerRay.ray_aabb(Vector3(0, 0, 2), Vector3.RIGHT,
			AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2)), 5.0) == INF, "ray misses the character box")

	rig.queue_free()
	await get_tree().process_frame


func _test_stale_grab_target() -> void:
	_section("freed grab targets")
	var rig := await _spawn_rig()
	var manager := InteractionManager.new()
	add_child(manager)
	var hand := FakeInteractor.new()
	add_child(hand)
	manager.register_interactor(hand)

	var poser: SkeletonPoser = rig.posers[0]
	var handle := poser.handle_for_bone(poser.skeleton.find_bone("Head"))
	hand.point = handle.global_position
	hand.grip = 1.0
	manager._process(0.016)
	_check(manager.grabbed_target(hand) != null, "joint grabbed before the model is replaced")

	# Replacing the model frees every handle while one is still held. That used to
	# throw "Trying to assign invalid previously freed instance" every frame.
	rig.install_model(_build_character(), "test://fixture2", "Fixture2")
	await get_tree().process_frame
	_check(not is_instance_valid(handle), "replacing the model frees the old handle")
	manager._process(0.016)
	# Grip is still held, so the manager is free to grab the matching joint of the
	# new model; what it must never do is keep the freed one.
	var current := manager.grabbed_target(hand)
	_check(current != handle, "the freed handle is no longer the held target")
	_check(current == null or is_instance_valid(current), "the manager only ever holds live targets")
	hand.grip = 0.0
	manager._process(0.016)
	_check(manager.grabbed_target(hand) == null, "releasing after a freed target is harmless")

	rig.queue_free()
	manager.queue_free()
	hand.queue_free()
	await get_tree().process_frame


func _test_scale_controls() -> void:
	_section("character scale")
	var rig := await _spawn_rig()
	var start := rig.scale.x
	rig.set_scale_multiplier(0.5)
	_check(is_equal_approx(rig.scale.x, start * 0.5), "scale multiplier halves the character")
	rig.set_scale_multiplier(99.0)
	_check(is_equal_approx(rig.scale.x, start * CharacterRig.MAX_SCALE_MULTIPLIER),
			"scale multiplier is clamped")
	rig.set_scale_multiplier(1.0)
	_check(rig.fit_to_height(1.8), "fit_to_height measures the loaded model")
	_check(absf(rig.world_height() - 1.8) < 0.05, "fitted height is 1.8 m (%.2f m)" % rig.world_height())
	rig.queue_free()
	await get_tree().process_frame

	# A character exported in centimetres must not arrive filling the room.
	var oversized := _build_character()
	oversized.scale = Vector3(4, 4, 4)
	var huge_rig := CharacterRig.new()
	add_child(huge_rig)
	huge_rig.install_model(oversized, "test://huge", "Huge")
	_check(absf(huge_rig.world_height() - CharacterRig.TARGET_HEIGHT) < 0.1,
			"oversized model is auto-fitted on load (%.2f m)" % huge_rig.world_height())
	huge_rig.queue_free()
	await get_tree().process_frame


func _test_scene_wiring() -> void:
	_section("scene wiring")
	_check(bool(ProjectSettings.get_setting("xr/shaders/enabled", false)),
			"XR shaders are enabled in the project settings")
	_check(int(ProjectSettings.get_setting("xr/openxr/environment_blend_mode", -1)) == 2,
			"passthrough is set to alpha blend")
	_check(bool(ProjectSettings.get_setting("xr/openxr/extensions/hand_tracking", false)),
			"hand tracking is requested from OpenXR")

	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		_check(false, "main scene loads")
		return
	var main := packed.instantiate()
	add_child(main)
	await get_tree().process_frame

	var has_environment := false
	var has_key_light := false
	for child in main.get_children():
		if child is WorldEnvironment:
			has_environment = true
		elif child is DirectionalLight3D:
			has_key_light = true
	_check(has_environment and has_key_light, "the scene lights the character (ambient + key light)")

	var controller := main.get_node_or_null("XROrigin3D/LeftController") as XRController3D
	_check(controller != null and controller.pose == &"aim",
			"controllers are bound to the aim pose so the laser points where you aim")
	var interactor := main.get_node_or_null("XROrigin3D/LeftController/Interactor") as XRInteractor
	_check(interactor != null, "controller interactor is wired")
	if interactor != null:
		_check(interactor.pointer != null, "controller interactor has a laser pointer")
		_check(not interactor.pointer.visible, "the pointer stays hidden until the controller is tracked")
	var hand := main.get_node_or_null("XROrigin3D/RightHand") as XRInteractor
	_check(hand != null and hand.pointer != null, "hand interactor has a laser pointer")

	main.queue_free()
	await get_tree().process_frame


func _test_model_scan_report() -> void:
	_section("model folder diagnostics")
	_check(ModelLibrary.package_name_from_data_dir("/data/user/0/com.example.vrcharacterposer/files")
			== "com.example.vrcharacterposer", "package name parsed from /data/user/0")
	_check(ModelLibrary.package_name_from_data_dir("/data/data/com.example.app/files")
			== "com.example.app", "package name parsed from /data/data")
	_check(ModelLibrary.package_name_from_data_dir("").is_empty(), "no package without a data dir")

	var library := ModelLibrary.new()
	_check(library.directories().has("res://models"), "bundled res://models folder is scanned")
	var report := library.scan_report()
	_check(report.size() == library.directories().size(), "scan report covers every directory")
	_check(not report.is_empty() and report[0].has("display") and report[0].has("models"),
			"scan report entries describe each folder")


# --- Helpers ---------------------------------------------------------------

func _spawn_rig() -> CharacterRig:
	var rig := CharacterRig.new()
	add_child(rig)
	rig.install_model(_build_character(), "test://fixture", "Fixture")
	await get_tree().process_frame
	return rig


func _cleanup() -> void:
	if FileAccess.file_exists("user://selftest_character.glb"):
		DirAccess.remove_absolute("user://selftest_character.glb")


class FakeInteractor extends XRInteractor:
	var point := Vector3.ZERO
	var basis_override := Basis.IDENTITY
	var grip := 0.0
	var tracking := true

	func get_grab_point() -> Vector3:
		return point

	func get_grab_basis() -> Basis:
		return basis_override

	func get_grip_strength() -> float:
		return grip

	func is_tracking() -> bool:
		return tracking
