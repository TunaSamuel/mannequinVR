class_name XRInteractor
extends Node3D
## Base class for anything that can grab things (a Touch controller or a hand).
##
## Grab targets only rely on this small surface, so controllers and hands feel
## identical to the posing code.

## 0..1 grip/pinch amount. Targets start a grab above ~0.65 and drop below ~0.35.
func get_grip_strength() -> float:
	return 0.0


## World-space point used for grabbing and for hover tests.
func get_grab_point() -> Vector3:
	return global_position


## World-space orientation of the grabbing hand/controller.
func get_grab_basis() -> Basis:
	return global_transform.basis.orthonormalized()


func is_tracking() -> bool:
	return false


func get_label() -> String:
	return name


## Short haptic tick; ignored by hands.
func pulse(_strength: float) -> void:
	pass
