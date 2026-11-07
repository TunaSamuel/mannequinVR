class_name InteractionManager
extends Node3D
## Routes grip/pinch/trigger input from every interactor to the nearest grab target.
##
## Targets opt in by joining the "grab_target" group and implementing:
##   can_grab(point), get_grab_priority(), get_grab_distance(point),
##   begin_grab(interactor), drag_grab(interactor), end_grab(interactor)
## and optionally set_hover(bool) / is_grabbed() / accepts_multiple_grabs() /
## uses_select_input().
##
## UI widgets (priority >= UI_PRIORITY, or uses_select_input() == true) are
## activated with the controller trigger / hand pinch.
## Bones and the character body are activated with the controller grip / hand pinch.

## Grip/trigger is analog, so use hysteresis to avoid chatter at the threshold.
const GRAB_START_THRESHOLD := 0.65
const GRAB_RELEASE_THRESHOLD := 0.35
const HAPTIC_STRENGTH := 0.35
## Priority at or above this value uses select/trigger instead of grip.
const UI_PRIORITY := 40

var _interactors: Array[XRInteractor] = []
var _grabbed: Dictionary = {}
var _input_down: Dictionary = {}
var _hovered: Dictionary = {}


func register_interactor(interactor: XRInteractor) -> void:
	if interactor != null and not _interactors.has(interactor):
		_interactors.append(interactor)
		interactor.tree_exiting.connect(_on_interactor_exiting.bind(interactor))


func interactors() -> Array[XRInteractor]:
	return _interactors


func _process(_delta: float) -> void:
	var targets := get_tree().get_nodes_in_group("grab_target")
	for interactor in _interactors:
		if not is_instance_valid(interactor):
			continue
		if not interactor.is_tracking():
			_release(interactor)
			_clear_hover(interactor)
			continue

		var target := _live_target(interactor)
		# While already grabbing, keep using the same input channel that started
		# the grab so releasing grip doesn't leave a trigger-held UI stuck, etc.
		var use_select := false
		if target != null and is_instance_valid(target):
			use_select = _target_uses_select(target)
		else:
			# Peek at whatever is under the pointer to choose the right input.
			var hover_candidate := _find_target(interactor, targets)
			use_select = hover_candidate != null and _target_uses_select(hover_candidate)

		var strength := interactor.get_select_strength() if use_select else interactor.get_grip_strength()
		var pressed: bool = _input_down.get(interactor, false)
		var threshold := GRAB_RELEASE_THRESHOLD if pressed else GRAB_START_THRESHOLD
		pressed = strength >= threshold
		_input_down[interactor] = pressed

		if pressed:
			if target == null or not is_instance_valid(target):
				target = _find_target(interactor, targets)
				if target != null:
					# Re-check channel: only start a grab if the press matches
					# the target's preferred input (prevents grip from clicking UI).
					if _target_uses_select(target) != use_select:
						var other := interactor.get_grip_strength() if use_select else interactor.get_select_strength()
						if other < GRAB_START_THRESHOLD:
							_update_hover(interactor, targets)
							continue
					_begin(interactor, target)
					_clear_hover(interactor)
					continue
			if target != null and is_instance_valid(target):
				target.call("drag_grab", interactor)
				continue

		if target != null:
			_release(interactor)
			continue

		_update_hover(interactor, targets)


func _target_uses_select(target: Node3D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target.has_method("uses_select_input"):
		return bool(target.call("uses_select_input"))
	if target.has_method("get_grab_priority"):
		return int(target.call("get_grab_priority")) >= UI_PRIORITY
	return false


func _find_target(interactor: XRInteractor, targets: Array) -> Node3D:
	var point := interactor.get_grab_point()
	var best: Node3D = null
	var best_priority := -1
	var best_distance := INF
	for node in targets:
		var target := node as Node3D
		if target == null or not is_instance_valid(target):
			continue
		if not target.has_method("can_grab") or not target.has_method("begin_grab"):
			continue
		if target.has_method("is_grabbed") and bool(target.call("is_grabbed")):
			var multi := target.has_method("accepts_multiple_grabs") and bool(target.call("accepts_multiple_grabs"))
			if not multi:
				continue
		if not bool(target.call("can_grab", point)):
			continue
		var priority := int(target.call("get_grab_priority")) if target.has_method("get_grab_priority") else 0
		var distance := float(target.call("get_grab_distance", point)) if target.has_method("get_grab_distance") else 0.0
		if priority > best_priority or (priority == best_priority and distance < best_distance):
			best = target
			best_priority = priority
			best_distance = distance
	return best


func _begin(interactor: XRInteractor, target: Node3D) -> void:
	_grabbed[interactor] = target
	# Handles and panel widgets can be freed while a grab is active (loading a
	# different model does exactly that). Drop the grab when the target goes.
	target.tree_exiting.connect(_on_target_exiting.bind(interactor), CONNECT_ONE_SHOT)
	target.call("begin_grab", interactor)
	interactor.pulse(HAPTIC_STRENGTH)


func _release(interactor: XRInteractor) -> void:
	var target := _live_target(interactor)
	_grabbed.erase(interactor)
	_input_down[interactor] = false
	if target != null:
		target.call("end_grab", interactor)


## Returns the grabbed target only while it is still alive. A freed node must
## never be assigned to a typed variable: Godot reports that as
## "Trying to assign invalid previously freed instance" and skips the frame.
func _live_target(interactor: XRInteractor) -> Node3D:
	var value: Variant = _grabbed.get(interactor)
	if value == null:
		return null
	if not is_instance_valid(value) or not value is Node3D:
		_grabbed.erase(interactor)
		_input_down[interactor] = false
		return null
	return value as Node3D


func _live_hover(interactor: XRInteractor) -> Node3D:
	var value: Variant = _hovered.get(interactor)
	if value == null:
		return null
	if not is_instance_valid(value) or not value is Node3D:
		_hovered.erase(interactor)
		return null
	return value as Node3D


func _on_target_exiting(interactor: XRInteractor) -> void:
	# Target is being freed (panel rebuild, model swap). Clear manager state;
	# the node itself is going away so end_grab is unnecessary.
	_grabbed.erase(interactor)
	_input_down[interactor] = false
	_hovered.erase(interactor)


func _update_hover(interactor: XRInteractor, targets: Array) -> void:
	var target := _find_target(interactor, targets)
	var previous := _live_hover(interactor)
	if previous == target:
		return
	_set_hover(previous, false)
	_set_hover(target, true)
	_hovered[interactor] = target


func _clear_hover(interactor: XRInteractor) -> void:
	var previous := _live_hover(interactor)
	_set_hover(previous, false)
	_hovered.erase(interactor)


func _set_hover(target: Node3D, hovered: bool) -> void:
	if target != null and is_instance_valid(target) and target.has_method("set_hover"):
		target.call("set_hover", hovered)


func _on_interactor_exiting(interactor: XRInteractor) -> void:
	_release(interactor)
	_clear_hover(interactor)
	_interactors.erase(interactor)


func grabbed_target(interactor: XRInteractor) -> Node3D:
	return _live_target(interactor)
