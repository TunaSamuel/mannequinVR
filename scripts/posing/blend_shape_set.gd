class_name BlendShapeSet
extends RefCounted
## Enumerates every blend shape (morph target) under a loaded model and applies
## weights to the owning MeshInstance3D nodes.

var entries: Array[Dictionary] = []
var _root: Node


func collect(root: Node) -> void:
	_root = root
	entries.clear()
	if root == null:
		return
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null:
			continue
		var node_path := String(root.get_path_to(instance))
		var array_mesh := instance.mesh as ArrayMesh
		for index in instance.get_blend_shape_count():
			var shape_name := "shape_%d" % index
			if array_mesh != null:
				shape_name = String(array_mesh.get_blend_shape_name(index))
			entries.append({
				"node": instance,
				"node_path": node_path,
				"index": index,
				"name": shape_name,
				"value": instance.get_blend_shape_value(index),
			})


func count() -> int:
	return entries.size()


## Name shown in the UI, disambiguated when several meshes share a shape name.
func display_name(entry_index: int) -> String:
	if entry_index < 0 or entry_index >= entries.size():
		return ""
	var entry := entries[entry_index]
	var shape_name: String = entry["name"]
	var duplicates := 0
	for other in entries:
		if String(other["name"]) == shape_name:
			duplicates += 1
	if duplicates <= 1:
		return shape_name
	return "%s (%s)" % [shape_name, String(entry["node_path"]).get_file()]


func set_value(entry_index: int, value: float) -> void:
	if entry_index < 0 or entry_index >= entries.size():
		return
	var entry := entries[entry_index]
	var instance: MeshInstance3D = entry["node"]
	if not is_instance_valid(instance) or instance.mesh == null:
		return
	var clamped := clampf(value, 0.0, 1.0)
	instance.set_blend_shape_value(int(entry["index"]), clamped)
	entry["value"] = clamped


func get_value(entry_index: int) -> float:
	if entry_index < 0 or entry_index >= entries.size():
		return 0.0
	return float(entries[entry_index]["value"])


func reset_all() -> void:
	for index in entries.size():
		set_value(index, 0.0)


## JSON-friendly snapshot of every weight.
func capture() -> Array:
	var data: Array = []
	for entry in entries:
		data.append({
			"node": entry["node_path"],
			"index": entry["index"],
			"name": entry["name"],
			"value": entry["value"],
		})
	return data


## Restores weights by mesh path and shape name, skipping shapes the current
## model does not have.
func apply(data: Array) -> int:
	if _root == null:
		return 0
	var applied := 0
	for item in data:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var record := item as Dictionary
		var wanted_name := String(record.get("name", ""))
		var wanted_node := String(record.get("node", ""))
		var value := clampf(float(record.get("value", 0.0)), 0.0, 1.0)
		for index in entries.size():
			var entry := entries[index]
			if String(entry["name"]) != wanted_name:
				continue
			if not wanted_node.is_empty() and String(entry["node_path"]) != wanted_node:
				continue
			set_value(index, value)
			applied += 1
	return applied
