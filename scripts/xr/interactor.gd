class_name XRInteractor
extends Node3D
## Base class for anything that can grab things (a Touch controller or a hand).
##
## Grab targets only rely on this small surface, so controllers and hands feel
## identical to the posing code. Every interactor also owns a visible laser
## pointer: it shows where the grab lands, which is what makes it obvious that
## joints and panel controls are interactive.

## 0..1 grip/pinch amount. Used for bones and character move/scale.
func get_grip_strength() -> float:
	return 0.0


## 0..1 select/trigger amount. Used for UI buttons and sliders.
## Controllers map this to the index trigger; hands fall back to pinch so
## the same gesture still works without controllers.
func get_select_strength() -> float:
	return get_grip_strength()


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


# --- Laser pointer ---------------------------------------------------------

var pointer: XRPointerRay
var pointer_enabled := true


func _ready() -> void:
	_ensure_pointer()


func _process(_delta: float) -> void:
	_update_pointer()


func _ensure_pointer() -> void:
	if pointer != null and is_instance_valid(pointer):
		return
	pointer = XRPointerRay.new()
	pointer.name = "Pointer"
	add_child(pointer)


## World-space start of the pointer ray.
func get_pointer_origin() -> Vector3:
	return global_position


## World-space direction of the pointer ray.
func get_pointer_direction() -> Vector3:
	return -global_transform.basis.z


## Grab point, preferring the laser hit so joints and panel controls can be
## operated at a distance.
func pointer_grab_point(fallback: Vector3) -> Vector3:
	if pointer != null and is_instance_valid(pointer) and pointer.visible and pointer.has_hit:
		return pointer.hit_point
	return fallback


func _update_pointer() -> void:
	if not pointer_enabled:
		if pointer != null and is_instance_valid(pointer):
			pointer.hide_ray()
		return
	_ensure_pointer()
	if not is_tracking():
		pointer.hide_ray()
		return
	pointer.update_ray(get_pointer_origin(), get_pointer_direction(),
			get_tree().get_nodes_in_group("grab_target"))
