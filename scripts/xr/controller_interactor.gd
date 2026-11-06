class_name ControllerInteractor
extends XRInteractor
## Grab source backed by an XRController3D (Touch controllers on Quest).
##
## Add this as a child of an XRController3D: the child sits at the controller's
## grip pose, so its transform is already the grab pose in world space.

const GRIP_ACTION := &"grip"
const GRIP_CLICK_ACTION := &"grip_click"

var _controller: XRController3D


func _ready() -> void:
	_controller = get_parent() as XRController3D
	if _controller == null:
		push_error("ControllerInteractor must be a child of an XRController3D.")


func get_grip_strength() -> float:
	if _controller == null:
		return 0.0
	# grip is analog on Touch controllers; grip_click covers runtimes that only
	# report the button.
	var analog := clampf(_controller.get_float(GRIP_ACTION), 0.0, 1.0)
	if _controller.is_button_pressed(GRIP_CLICK_ACTION):
		return maxf(analog, 1.0)
	return analog


func is_tracking() -> bool:
	if _controller == null:
		return false
	return _controller.get_is_active() and _controller.get_has_tracking_data()


func get_label() -> String:
	if _controller == null:
		return name
	return "%s controller" % ("Left" if _controller.get_tracker_hand() == XRPositionalTracker.TRACKER_HAND_LEFT else "Right")


func pulse(strength: float) -> void:
	if _controller != null and _controller.get_is_active():
		_controller.trigger_haptic_pulse(&"haptic", 0.0, clampf(strength, 0.0, 1.0), 0.06, 0.0)
