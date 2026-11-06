class_name ModelLoader
extends RefCounted
## Runtime loading and validation of character models.
##
## `.glb` / `.gltf` are loaded through GLTFDocument, which keeps skeletons,
## blend shapes, materials and hierarchy intact. FBX is intentionally not
## loaded at runtime; models should be converted to GLB (Blender, ufbx, ...).

const SUPPORTED_EXTENSIONS: PackedStringArray = ["glb", "gltf"]
const HEAVY_TRIANGLE_BUDGET := 250000
const HEAVY_BLEND_SHAPE_BUDGET := 120


class Result:
	var ok := false
	var error := ""
	var scene: Node3D
	var stats: Dictionary = {}
	var warnings: PackedStringArray = []


## Loads a model from disk. The returned scene is unparented; ownership passes
## to the caller, who must free it or add it to the tree.
static func load_from_path(path: String) -> Result:
	var result := Result.new()

	var extension := path.get_extension().to_lower()
	if not SUPPORTED_EXTENSIONS.has(extension):
		if extension == "fbx":
			result.error = "FBX is not supported at runtime. Convert it to GLB first."
		else:
			result.error = "Unsupported format '.%s'. Use .glb or .gltf." % extension
		return result

	if not FileAccess.file_exists(path):
		result.error = "File not found: %s" % path
		return result

	var document := GLTFDocument.new()
	var state := GLTFState.new()
	# This app poses characters itself; importing clips would only cost memory.
	state.create_animations = false

	var error := document.append_from_file(path, state, 0, path.get_base_dir())
	if error != OK:
		result.error = "Could not parse '%s' (glTF error %d)." % [path.get_file(), error]
		return result

	var scene: Node = document.generate_scene(state, 30.0, false, false)
	if scene == null:
		result.error = "glTF parsed but the scene could not be generated."
		return result
	if not scene is Node3D:
		scene.free()
		result.error = "Model root is not a 3D node."
		return result

	var root := scene as Node3D
	root.name = "LoadedModel"
	result.scene = root
	result.stats = analyze(root)
	result.warnings = warnings_for(result.stats)
	result.ok = true
	return result


## Collects mesh / skeleton / blend shape information for a model subtree.
static func analyze(root: Node3D) -> Dictionary:
	var collector := _Collector.new()
	collector.walk(root, Transform3D())
	return collector.to_dictionary()


static func warnings_for(stats: Dictionary) -> PackedStringArray:
	var warnings: PackedStringArray = []
	if int(stats.get("skeletons", 0)) == 0:
		warnings.append("No skeleton found: bone posing is unavailable for this model.")
	if int(stats.get("mesh_instances", 0)) == 0:
		warnings.append("No meshes found: nothing to display.")
	if int(stats.get("triangles", 0)) > HEAVY_TRIANGLE_BUDGET:
		warnings.append("Heavy mesh (%s triangles): expect a lower frame rate on Quest."
				% _thousands(int(stats["triangles"])))
	if int(stats.get("blend_shapes", 0)) > HEAVY_BLEND_SHAPE_BUDGET:
		warnings.append("This model has %d blend shapes, which can be expensive to animate."
				% int(stats["blend_shapes"]))
	return warnings


## All skeletons in the subtree, in tree order.
static func collect_skeletons(root: Node) -> Array:
	var found: Array = []
	for node in root.find_children("*", "Skeleton3D", true, false):
		found.append(node)
	return found


## All skinned mesh instances in the subtree, in tree order.
static func collect_mesh_instances(root: Node) -> Array:
	var found: Array = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).mesh != null:
			found.append(node)
	return found


static func _thousands(value: int) -> String:
	var text := str(value)
	var out := ""
	var count := 0
	for index in range(text.length() - 1, -1, -1):
		out = text[index] + out
		count += 1
		if count % 3 == 0 and index > 0:
			out = "," + out
	return out


class _Collector:
	var mesh_instances := 0
	var triangles := 0
	var vertices := 0
	var skeletons := 0
	var bones := 0
	var blend_shapes := 0
	var blend_shape_names: Array[String] = []
	var aabb := AABB()
	var has_bounds := false

	func walk(node: Node, parent_transform: Transform3D) -> void:
		var transform := parent_transform
		if node is Node3D:
			transform = parent_transform * (node as Node3D).transform
		if node is Skeleton3D:
			skeletons += 1
			bones += (node as Skeleton3D).get_bone_count()
		elif node is MeshInstance3D:
			_collect_mesh(node as MeshInstance3D, transform)
		for child in node.get_children():
			walk(child, transform)

	func _collect_mesh(instance: MeshInstance3D, transform: Transform3D) -> void:
		var mesh := instance.mesh
		if mesh == null:
			return
		mesh_instances += 1
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			if arrays.is_empty():
				continue
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			if indices is PackedInt32Array and not (indices as PackedInt32Array).is_empty():
				triangles += int((indices as PackedInt32Array).size() / 3.0)
				vertices += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			else:
				var vertex_count := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
				triangles += int(vertex_count / 3.0)
				vertices += vertex_count
		var array_mesh := mesh as ArrayMesh
		for index in instance.get_blend_shape_count():
			blend_shapes += 1
			if array_mesh != null:
				var shape_name := String(array_mesh.get_blend_shape_name(index))
				if not blend_shape_names.has(shape_name):
					blend_shape_names.append(shape_name)
		_merge_bounds(transform, mesh.get_aabb())

	func _merge_bounds(transform: Transform3D, bounds: AABB) -> void:
		if bounds.size == Vector3.ZERO:
			return
		for corner in range(8):
			var point := bounds.position + Vector3(
					bounds.size.x * float(corner & 1),
					bounds.size.y * float((corner >> 1) & 1),
					bounds.size.z * float((corner >> 2) & 1))
			var world := transform * point
			if not has_bounds:
				aabb = AABB(world, Vector3.ZERO)
				has_bounds = true
			else:
				aabb = aabb.expand(world)

	func to_dictionary() -> Dictionary:
		var height := aabb.size.y if has_bounds else 0.0
		return {
			"mesh_instances": mesh_instances,
			"triangles": triangles,
			"vertices": vertices,
			"skeletons": skeletons,
			"bones": bones,
			"blend_shapes": blend_shapes,
			"blend_shape_names": blend_shape_names,
			"aabb": aabb,
			"height": height,
			"has_bounds": has_bounds,
		}
