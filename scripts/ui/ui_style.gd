class_name UIStyle
extends RefCounted
## Shared look for the in-world UI. Materials are cached so a panel with dozens
## of pieces still uses a handful of materials.

const COLOR_PANEL := Color(0.055, 0.065, 0.090, 0.93)
const COLOR_BUTTON := Color(0.150, 0.180, 0.230, 0.97)
const COLOR_BUTTON_HOVER := Color(0.240, 0.330, 0.440, 1.0)
const COLOR_BUTTON_ACTIVE := Color(0.200, 0.620, 0.620, 1.0)
const COLOR_BUTTON_DISABLED := Color(0.100, 0.110, 0.130, 0.85)
const COLOR_TRACK := Color(0.120, 0.140, 0.180, 1.0)
const COLOR_FILL := Color(0.310, 0.820, 0.800, 1.0)
const COLOR_KNOB := Color(0.920, 0.960, 1.0, 1.0)
const COLOR_TEXT := Color(0.910, 0.940, 1.000, 1.0)
const COLOR_TEXT_DIM := Color(0.620, 0.680, 0.780, 1.0)
const COLOR_TEXT_ON_ACTIVE := Color(0.035, 0.090, 0.090, 1.0)

## Metres per font pixel. Text height = font_size * FONT_PIXEL_SIZE.
const FONT_PIXEL_SIZE := 0.00055

static var _materials: Dictionary = {}


static func quad_material(color: Color, priority: int = 1) -> StandardMaterial3D:
	var key := "%s_%d_%s" % [color.to_html(), priority, "t" if color.a < 0.999 else "o"]
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if color.a < 0.999:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.disable_receive_shadows = true
	material.render_priority = priority
	_materials[key] = material
	return material


static func unshaded_material(color: Color) -> StandardMaterial3D:
	var key := "unshaded_%s" % color.to_html()
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.disable_receive_shadows = true
	_materials[key] = material
	return material


## Creates a Label3D whose glyph height is close to `height_metres`.
static func make_label(text: String, height_metres: float, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.pixel_size = FONT_PIXEL_SIZE
	label.font_size = maxi(int(round(height_metres / FONT_PIXEL_SIZE)), 12)
	label.modulate = color
	label.outline_size = 0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.render_priority = 3
	return label


static func quad(size: Vector2, color: Color, priority: int = 1) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var quad_mesh := QuadMesh.new()
	quad_mesh.size = size
	mesh_instance.mesh = quad_mesh
	mesh_instance.material_override = quad_material(color, priority)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh_instance
