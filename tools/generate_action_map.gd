extends SceneTree
## Regenerates res://openxr_action_map.tres from Godot's built-in OpenXR
## defaults (Oculus Touch, Vive, WMR, KHR simple controller and the hand
## interaction profile). Run with:
##
##   godot --headless --path . -s tools/generate_action_map.gd
##
## Keeping the map in version control means the project's input bindings are
## explicit and customisable in the OpenXR Action Map editor.

const OUTPUT_PATH := "res://openxr_action_map.tres"


func _initialize() -> void:
	var action_map := OpenXRActionMap.new()
	action_map.create_default_action_sets()
	var error := ResourceSaver.save(action_map, OUTPUT_PATH)
	if error != OK:
		printerr("Failed to write %s (error %d)" % [OUTPUT_PATH, error])
		quit(1)
		return
	print("Wrote %s (%d action sets, %d interaction profiles)" % [
		OUTPUT_PATH, action_map.get_action_sets().size(),
		action_map.get_interaction_profiles().size(),
	])
	quit()
