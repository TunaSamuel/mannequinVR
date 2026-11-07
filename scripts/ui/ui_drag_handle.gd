class_name UIDragHandle
extends UIButton3D
## A grab bar that moves a target node (used to reposition the panel).

var target: Node3D
var _offset_local := Vector3.ZERO


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
		_offset_local = target.global_transform.affine_inverse() * interactor.get_grab_point()


func drag_grab(interactor: XRInteractor) -> void:
	if _grabbed_by != interactor or target == null:
		return
	target.global_position = interactor.get_grab_point() - target.global_transform.basis * _offset_local


func end_grab(_interactor: XRInteractor) -> void:
	_grabbed_by = null
	_pressed = false
	_refresh()
