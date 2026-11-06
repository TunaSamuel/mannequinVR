class_name PoseStore
extends RefCounted
## Reads and writes pose presets as versioned JSON files in `user://poses`.

const FORMAT_VERSION := 1
const POSE_DIRECTORY := "user://poses"
const FILE_PREFIX := "pose_"


static func ensure_directory() -> void:
	if not DirAccess.dir_exists_absolute(POSE_DIRECTORY):
		DirAccess.make_dir_recursive_absolute(POSE_DIRECTORY)


## Writes a pose document and returns its path ("" on failure).
static func save(document: Dictionary) -> String:
	ensure_directory()
	var stamp := Time.get_datetime_dict_from_system()
	var file_name := "%s%04d%02d%02d_%02d%02d%02d.json" % [
		FILE_PREFIX, stamp["year"], stamp["month"], stamp["day"],
		stamp["hour"], stamp["minute"], stamp["second"],
	]
	var path := POSE_DIRECTORY.path_join(file_name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("PoseStore: could not write %s" % path)
		return ""
	document["version"] = FORMAT_VERSION
	document["created"] = Time.get_unix_time_from_system()
	file.store_string(JSON.stringify(document, "  "))
	file.close()
	return path


## Saved poses, newest first: { path, label, model_name, version }
static func list_poses() -> Array[Dictionary]:
	var poses: Array[Dictionary] = []
	var access := DirAccess.open(POSE_DIRECTORY)
	if access == null:
		return poses
	access.list_dir_begin()
	var file_name := access.get_next()
	while not file_name.is_empty():
		if not access.current_is_dir() and file_name.begins_with(FILE_PREFIX) \
				and file_name.get_extension().to_lower() == "json":
			var path := POSE_DIRECTORY.path_join(file_name)
			var summary := {
				"path": path,
				"label": _label_from_file_name(file_name),
				"model_name": "",
				"version": 0,
			}
			var document := read(path)
			if not document.is_empty():
				summary["model_name"] = String(document.get("model_name", ""))
				summary["version"] = int(document.get("version", 0))
				if not String(document.get("created_label", "")).is_empty():
					summary["label"] = String(document["created_label"])
			poses.append(summary)
		file_name = access.get_next()
	access.list_dir_end()
	poses.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["path"]) > String(b["path"])
	)
	return poses


## Reads and validates a pose document; returns {} when unreadable.
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("PoseStore: %s is not a pose file" % path)
		return {}
	var document := parsed as Dictionary
	var version := int(document.get("version", 0))
	if version <= 0 or version > FORMAT_VERSION:
		push_warning("PoseStore: unsupported pose version %d in %s" % [version, path])
		return {}
	return document


static func delete(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(path) == OK


static func _label_from_file_name(file_name: String) -> String:
	var base := file_name.get_basename().trim_prefix(FILE_PREFIX)
	var parts := base.split("_")
	if parts.size() == 2 and parts[0].length() == 8:
		return "%s-%s-%s %s:%s" % [
			parts[0].substr(6, 2), parts[0].substr(4, 2), parts[0].substr(0, 4),
			parts[1].substr(0, 2), parts[1].substr(2, 2),
		]
	return base
