class_name ModelLibrary
extends RefCounted
## Finds character models on disk and remembers recently used ones.
##
## On Quest the app cannot ask for broad storage access without Play/Meta
## review friction, so the primary location is the app's own external files
## directory, which is reachable over USB (MTP) and adb without permissions:
##
##     /storage/emulated/0/Android/data/<package>/files/models
##
## On desktop (and in the editor) models are read from `user://models` and from
## a project-local `models/` folder so the loader can be exercised off-device.

const SUPPORTED_EXTENSIONS: PackedStringArray = ["glb", "gltf"]
const RECENTS_PATH := "user://recent_models.json"
const MAX_RECENTS := 8
const EXTERNAL_ROOT := "/storage/emulated/0/Android/data/%s/files/models"
const LEGACY_SDCARD_ROOT := "/sdcard/Android/data/%s/files/models"

var _directories: PackedStringArray = []


func _init() -> void:
	_directories = resolve_directories()


## Directories that are scanned for models, in priority order.
static func resolve_directories() -> PackedStringArray:
	var dirs: PackedStringArray = []

	var override := OS.get_environment("VR_POSER_MODELS")
	if override.is_empty():
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--models-dir="):
				override = arg.trim_prefix("--models-dir=")
	if not override.is_empty():
		dirs.append(override)

	dirs.append("user://models")
	if not OS.has_feature("standalone"):
		# Running from source: allow a repo-local models folder.
		dirs.append(ProjectSettings.globalize_path("res://models"))

	if OS.has_feature("android"):
		var package := android_package_name()
		if not package.is_empty():
			dirs.append(EXTERNAL_ROOT % package)
			dirs.append(LEGACY_SDCARD_ROOT % package)

	return dirs


## Best-effort lookup of this app's Android package name, without Java bridging.
static func android_package_name() -> String:
	if not OS.has_feature("android"):
		return ""
	# For an Android app process, /proc/self/cmdline holds the package name.
	var cmdline := FileAccess.get_file_as_string("/proc/self/cmdline")
	for part in cmdline.split("\u0000", false):
		var candidate := part.strip_edges()
		if candidate.count(".") >= 1 and not candidate.contains("/") and not candidate.contains(":"):
			return candidate
	# Fallback: /data/app/~~hash==/<package>-hash==/base.apk
	var executable := OS.get_executable_path()
	var marker := executable.find("/data/app/")
	if marker != -1:
		var parts := executable.substr(marker).split("/", false)
		if parts.size() > 3:
			var package_part := parts[2]
			var dash := package_part.rfind("-")
			return package_part if dash == -1 else package_part.substr(0, dash)
	return ""


func directories() -> PackedStringArray:
	return _directories


## Creates the user-writable model folders so they exist for the user to fill.
func ensure_directories() -> void:
	for dir in _directories:
		if dir.begins_with("res://"):
			continue
		if DirAccess.dir_exists_absolute(dir):
			continue
		DirAccess.make_dir_recursive_absolute(dir)


## Scans all known directories. Returns entries sorted by name:
## { path: String, name: String, directory: String, size: int }
func scan() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var seen := {}
	for dir in _directories:
		var access := DirAccess.open(dir)
		if access == null:
			continue
		access.list_dir_begin()
		var file_name := access.get_next()
		while not file_name.is_empty():
			if not access.current_is_dir() and not file_name.begins_with("."):
				var ext := file_name.get_extension().to_lower()
				if SUPPORTED_EXTENSIONS.has(ext):
					var path := dir.path_join(file_name)
					if not seen.has(path):
						seen[path] = true
						entries.append({
							"path": path,
							"name": file_name.get_basename(),
							"directory": dir,
							"size": _file_size(path),
						})
			file_name = access.get_next()
		access.list_dir_end()
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["name"]).naturalnocasecmp_to(String(b["name"])) < 0
	)
	return entries


static func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var size := file.get_length()
	file.close()
	return size


## Recent model paths that still exist, most recent first.
func recents() -> PackedStringArray:
	var result: PackedStringArray = []
	for path in _read_recents():
		if FileAccess.file_exists(path):
			result.append(path)
	return result


func mark_recent(path: String) -> void:
	var previous := _read_recents()
	var recents: PackedStringArray = [path]
	for existing in previous:
		if existing != path and recents.size() < MAX_RECENTS:
			recents.append(existing)
	var file := FileAccess.open(RECENTS_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"version": 1, "paths": recents}))
	file.close()


func _read_recents() -> PackedStringArray:
	var result: PackedStringArray = []
	if not FileAccess.file_exists(RECENTS_PATH):
		return result
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RECENTS_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return result
	var paths: Variant = (parsed as Dictionary).get("paths", [])
	if typeof(paths) != TYPE_ARRAY:
		return result
	for path in paths:
		if typeof(path) == TYPE_STRING:
			result.append(path)
	return result


## Human readable size, e.g. "1.4 MB".
static func format_size(bytes: int) -> String:
	if bytes >= 1024 * 1024:
		return "%.1f MB" % (bytes / 1048576.0)
	if bytes >= 1024:
		return "%.0f KB" % (bytes / 1024.0)
	return "%d B" % bytes
