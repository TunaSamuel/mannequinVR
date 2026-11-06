class_name HandInteractor
extends XRInteractor
## Hand-tracking grab source.
##
## Pinch is derived from OpenXR hand joints: when thumb tip and index tip come
## together the hand grips, and the midpoint of the two fingertips is the grab
## point. Joint poses are reported in play space, so they are transformed by the
## XROrigin3D before use.

enum Hand { LEFT, RIGHT }

## Finger separation (metres) mapped to grip strength 1 .. 0.
const PINCH_CLOSED_DISTANCE := 0.022
const PINCH_OPEN_DISTANCE := 0.058

@export var hand: Hand = Hand.LEFT

var _openxr: OpenXRInterface
var _origin: XROrigin3D
var _tracking := false


func _ready() -> void:
	super._ready()
	_openxr = XRServer.find_interface("OpenXR") as OpenXRInterface
	_origin = _find_origin()
	# Only worth flagging while a real session is running: without a headset the
	# interface exists but is never initialised.
	if _openxr != null and _openxr.is_initialized() and not _openxr.is_hand_tracking_supported():
		push_warning("Hand tracking is not supported by the current OpenXR runtime.")


func _find_origin() -> XROrigin3D:
	var node := get_parent()
	while node != null:
		if node is XROrigin3D:
			return node as XROrigin3D
		node = node.get_parent()
	return null


func _hand_index() -> int:
	return OpenXRInterface.HAND_LEFT if hand == Hand.LEFT else OpenXRInterface.HAND_RIGHT


func is_tracking() -> bool:
	if _openxr == null or _origin == null:
		return false
	if not _openxr.is_hand_tracking_supported():
		return false
	# Ignore hands synthesised from controllers: the controller interactor wins.
	if _openxr.get_hand_tracking_source(_hand_index()) != OpenXRInterface.HAND_TRACKED_SOURCE_UNOBSTRUCTED:
		return false
	return _joint_valid(OpenXRInterface.HAND_JOINT_THUMB_TIP) \
			and _joint_valid(OpenXRInterface.HAND_JOINT_INDEX_TIP)


func _joint_valid(joint: int) -> bool:
	var flags := _openxr.get_hand_joint_flags(_hand_index(), joint)
	return (flags & OpenXRInterface.HAND_JOINT_POSITION_VALID) != 0


func _joint_transform(joint: int) -> Transform3D:
	return _origin.global_transform * Transform3D(
			Basis(_openxr.get_hand_joint_rotation(_hand_index(), joint)),
			_openxr.get_hand_joint_position(_hand_index(), joint))


func get_grip_strength() -> float:
	if not is_tracking():
		return 0.0
	var thumb := _joint_transform(OpenXRInterface.HAND_JOINT_THUMB_TIP).origin
	var index := _joint_transform(OpenXRInterface.HAND_JOINT_INDEX_TIP).origin
	var distance := thumb.distance_to(index)
	return clampf(inverse_lerp(PINCH_OPEN_DISTANCE, PINCH_CLOSED_DISTANCE, distance), 0.0, 1.0)


## The laser starts at the index fingertip and follows the pointing finger, so
## far-away handles and panel controls can be pinched. When the ray misses, the
## pinch midpoint keeps direct touch working exactly as before.
func get_pointer_origin() -> Vector3:
	if not is_tracking():
		return global_position
	return _joint_transform(OpenXRInterface.HAND_JOINT_INDEX_TIP).origin


func get_pointer_direction() -> Vector3:
	if not is_tracking():
		return -global_transform.basis.z
	var tip := _joint_transform(OpenXRInterface.HAND_JOINT_INDEX_TIP).origin
	var base := _joint_transform(OpenXRInterface.HAND_JOINT_INDEX_INTERMEDIATE).origin
	var direction := tip - base
	if direction.length_squared() < 0.000001:
		return -global_transform.basis.z
	return direction.normalized()


func get_grab_point() -> Vector3:
	if not is_tracking():
		return global_position
	var thumb := _joint_transform(OpenXRInterface.HAND_JOINT_THUMB_TIP).origin
	var index := _joint_transform(OpenXRInterface.HAND_JOINT_INDEX_TIP).origin
	return pointer_grab_point((thumb + index) * 0.5)


func get_grab_basis() -> Basis:
	if not is_tracking():
		return global_transform.basis.orthonormalized()
	return _joint_transform(OpenXRInterface.HAND_JOINT_WRIST).basis.orthonormalized()


func get_label() -> String:
	return "Left hand" if hand == Hand.LEFT else "Right hand"
