class_name XRPointerRay
extends Node3D
## A visible laser plus a cursor dot: shows where a hand/controller is aiming and
## whether that spot can be grabbed. The interactor also uses the hit point as
## its grab point, so pointing at a joint or panel control works at arm's length.
##
## Targets may implement `ray_hit(origin, direction, max_distance) -> float`
## (distance along the ray, INF for a miss). Anything without it falls back to a
## small sphere around the node's origin, which keeps new grab targets working
## without extra code.

const MAX_DISTANCE := 1.7
const LINE_WIDTH := 0.0018
const CURSOR_RADIUS := 0.0065
const DEFAULT_RADIUS := 0.05
const LINE_COLOR := Color(0.42, 0.88, 1.0, 0.45)
const LINE_HIT_COLOR := Color(1.0, 0.78, 0.30, 0.95)
const CURSOR_COLOR := Color(1.0, 0.90, 0.55, 1.0)

var enabled := true
var has_hit := false
var hit_point := Vector3.ZERO
var hit_target: Node3D
var hit_distance := 0.0

var _line: MeshInstance3D
var _cursor: MeshInstance3D
var _line_material: StandardMaterial3D
var _hit_material: StandardMaterial3D
var _cursor_material: StandardMaterial3D


func _ready() -> void:
	_ensure_visuals()
	visible = false


func _ensure_visuals() -> void:
	if _line != null:
		return
	var box := BoxMesh.new()
	box.size = Vector3(LINE_WIDTH, LINE_WIDTH, 1.0)
	_line_material = _make_material(LINE_COLOR)
	_hit_material = _make_material(LINE_HIT_COLOR)

	_line = MeshInstance3D.new()
	_line.name = "Line"
	_line.mesh = box
	_line.material_override = _line_material
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_line.top_level = true
	add_child(_line)

	var sphere := SphereMesh.new()
	sphere.radius = CURSOR_RADIUS
	sphere.height = CURSOR_RADIUS * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	_cursor_material = _make_material(CURSOR_COLOR)
	_cursor = MeshInstance3D.new()
	_cursor.name = "Cursor"
	_cursor.mesh = sphere
	_cursor.material_override = _cursor_material
	_cursor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cursor.top_level = true
	_cursor.visible = false
	add_child(_cursor)


static func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# A pointer you cannot see through the character is not much use.
	material.no_depth_test = true
	material.render_priority = 4
	return material


## Casts a ray at every grab target and returns {} or
## { target: Node3D, point: Vector3, distance: float }.
static func cast(origin: Vector3, direction: Vector3, max_distance: float,
		targets: Array) -> Dictionary:
	if direction.length_squared() < 0.000001:
		return {}
	var dir := direction.normalized()
	var best_distance := max_distance
	var best_target: Node3D = null

	for node in targets:
		var target := node as Node3D
		if target == null or not is_instance_valid(target):
			continue
		var distance := INF
		if target.has_method("ray_hit"):
			distance = float(target.call("ray_hit", origin, dir, max_distance))
		elif target.has_method("get_grab_radius"):
			distance = ray_sphere(origin, dir, target.global_position,
					float(target.call("get_grab_radius")), max_distance)
		else:
			distance = ray_sphere(origin, dir, target.global_position, DEFAULT_RADIUS, max_distance)
		if distance < best_distance:
			best_distance = distance
			best_target = target

	if best_target == null:
		return {}
	return {"target": best_target, "distance": best_distance, "point": origin + dir * best_distance}


## Distance along the ray to the closest approach inside a sphere, or INF.
static func ray_sphere(origin: Vector3, direction: Vector3, center: Vector3,
		radius: float, max_distance: float) -> float:
	var to_center := center - origin
	var along := to_center.dot(direction)
	if along < -radius:
		return INF
	var t := maxf(along, 0.0)
	if t > max_distance + radius:
		return INF
	if (origin + direction * t).distance_to(center) > radius:
		return INF
	return t


## Slab test against an AABB. Returns the entry distance clamped to the ray
## start (so a ray beginning inside the box hits at 0), or INF.
static func ray_aabb(origin: Vector3, direction: Vector3, box: AABB, max_distance: float) -> float:
	if box.size == Vector3.ZERO:
		return INF
	var near := 0.0
	var far := max_distance
	for axis in 3:
		var direction_axis := _axis(direction, axis)
		var origin_axis := _axis(origin, axis)
		var low := _axis(box.position, axis)
		var high := low + _axis(box.size, axis)
		if absf(direction_axis) < 0.000001:
			if origin_axis < low or origin_axis > high:
				return INF
			continue
		var first := (low - origin_axis) / direction_axis
		var second := (high - origin_axis) / direction_axis
		if first > second:
			var swap := first
			first = second
			second = swap
		near = maxf(near, first)
		far = minf(far, second)
		if near > far:
			return INF
	return near


## Ray against the local XY plane of a UI node. Returns
## { x, y, distance } in that node's local space, or {} when it misses.
static func ray_plane_local(node: Node3D, origin: Vector3, direction: Vector3) -> Dictionary:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return {}
	var inverse := node.global_transform.affine_inverse()
	var local_origin := inverse * origin
	var local_direction := inverse.basis * direction
	if absf(local_direction.z) < 0.000001:
		return {}
	var t := -local_origin.z / local_direction.z
	if t <= 0.0:
		return {}
	var local_point := local_origin + local_direction * t
	var world_point := node.global_transform * local_point
	return {
		"x": local_point.x,
		"y": local_point.y,
		"distance": origin.distance_to(world_point),
	}


static func _axis(value: Vector3, axis: int) -> float:
	match axis:
		0:
			return value.x
		1:
			return value.y
		_:
			return value.z


func update_ray(origin: Vector3, direction: Vector3, targets: Array) -> void:
	if not enabled:
		hide_ray()
		return
	_ensure_visuals()
	var dir := direction
	if dir.length_squared() < 0.000001:
		dir = Vector3.FORWARD
	dir = dir.normalized()

	var result := cast(origin, dir, MAX_DISTANCE, targets)
	has_hit = not result.is_empty()
	if has_hit:
		hit_target = result["target"]
		hit_distance = float(result["distance"])
		hit_point = result["point"]
	else:
		hit_target = null
		hit_distance = MAX_DISTANCE
		hit_point = origin + dir * MAX_DISTANCE

	_draw(origin, dir)
	visible = true


func hide_ray() -> void:
	has_hit = false
	hit_target = null
	visible = false


func _draw(origin: Vector3, direction: Vector3) -> void:
	var length := maxf(origin.distance_to(hit_point), 0.002)
	var up := Vector3.UP
	if absf(direction.dot(Vector3.UP)) > 0.98:
		up = Vector3.RIGHT
	_line.global_transform = Transform3D(Basis.looking_at(direction, up), origin + direction * length * 0.5)
	_line.scale = Vector3(1.0, 1.0, length)
	_line.material_override = _hit_material if has_hit else _line_material
	_cursor.visible = has_hit
	if has_hit:
		_cursor.global_position = hit_point
