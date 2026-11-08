class_name UIDragHandle
extends UIButton3D
## A grab bar that moves and yaws a target node (used to reposition the panel).

var target: Node3D
var _offset_local := Vector3.ZERO
var _start_target_basis := Basis()
var _start_interactor_yaw := 0.0


## Drag handle needs a sustained grab, unlike normal buttons.
func is_click_target() -> bool:
	return false


func begin_grab(interactor: XRInteractor) -> void:
	if not enabled:
		return
	_grabbed_by = interactor
	_pressed = true
	_refresh()
	if target != null:
		if target.has_method("set_auto_face"):
			target.call("set_auto_face", false)
		_start_target_basis = target.global_transform.basis.orthonormalized()
		var ib := interactor.get_grab_basis().orthonormalized()
		_start_interactor_yaw = atan2(ib.z.x, ib.z.z)
		_offset_local = _start_target_basis.inverse() * (interactor.get_grab_point() - target.global_position)


func drag_grab(interactor: XRInteractor) -> void:
	if _grabbed_by != interactor or target == null:
		return
	var ib := interactor.get_grab_basis().orthonormalized()
	var yaw_now := atan2(ib.z.x, ib.z.z)
	var delta_yaw := yaw_now - _start_interactor_yaw
	var rotation := Basis(Vector3.UP, delta_yaw) * _start_target_basis
	var world_offset := rotation * _offset_local
	target.global_transform = Transform3D(rotation, interactor.get_grab_point() - world_offset)


func end_grab(_interactor: XRInteractor) -> void:
	_grabbed_by = null
	_pressed = false
	_refresh()
	# Resume facing the user after a short intentional placement.
	if target != null and target.has_method("set_auto_face"):
		target.call("set_auto_face", true)
