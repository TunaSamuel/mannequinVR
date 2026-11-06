class_name InteractionManager
extends Node3D
## Routes grip/pinch input from every interactor to the nearest grab target.
##
## Targets opt in by joining the "grab_target" group and implementing:
##   can_grab(point), get_grab_priority(), get_grab_distance(point),
##   begin_grab(interactor), drag_grab(interactor), end_grab(interactor)
## and optionally set_hover(bool) / is_grabbed() / accepts_multiple_grabs().

## Grip is analog, so use hysteresis to avoid chatter at the threshold.
const GRAB_START_THRESHOLD := 0.65
const GRAB_RELEASE_THRESHOLD := 0.35
const HAPTIC_STRENGTH := 0.35

var _interactors: Array[XRInteractor] = []
var _grabbed: Dictionary = {}
var _grip_down: Dictionary = {}
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

		var target: Node3D = _grabbed.get(interactor)
		var strength := interactor.get_grip_strength()
		var pressed: bool = _grip_down.get(interactor, false)
		var threshold := GRAB_RELEASE_THRESHOLD if pressed else GRAB_START_THRESHOLD
		pressed = strength >= threshold
		_grip_down[interactor] = pressed

		if pressed:
			if target == null or not is_instance_valid(target):
				target = _find_target(interactor, targets)
				if target != null:
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
	target.call("begin_grab", interactor)
	interactor.pulse(HAPTIC_STRENGTH)


func _release(interactor: XRInteractor) -> void:
	var target: Node3D = _grabbed.get(interactor)
	_grabbed.erase(interactor)
	_grip_down[interactor] = false
	if target != null and is_instance_valid(target):
		target.call("end_grab", interactor)


func _update_hover(interactor: XRInteractor, targets: Array) -> void:
	var target := _find_target(interactor, targets)
	var previous: Node3D = _hovered.get(interactor)
	if previous == target:
		return
	_set_hover(previous, false)
	_set_hover(target, true)
	_hovered[interactor] = target


func _clear_hover(interactor: XRInteractor) -> void:
	var previous: Node3D = _hovered.get(interactor)
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
	return _grabbed.get(interactor)
