class_name CharacterRig
extends Node3D
## Owns the loaded character: its transform, skeletons, bone handles and blend
## shapes. Also provides the grab target that moves/scales the character.

signal model_changed(info: Dictionary)
signal model_cleared
signal status_message(message: String)
signal pose_edited

const TARGET_HEIGHT := 1.6
const MIN_NATURAL_HEIGHT := 0.55
const MAX_NATURAL_HEIGHT := 2.0
const GRAB_MARGIN := 0.04
const MIN_SCALE_MULTIPLIER := 0.2
const MAX_SCALE_MULTIPLIER := 3.0
## World-space floor height (CharacterRoot Y) the Floor slider dials.
const MIN_FLOOR_Y := -0.25
const MAX_FLOOR_Y := 2.0
const UNDO_LIMIT := 40

var model_root: Node3D
var posing_root: Node3D
var posers: Array[SkeletonPoser] = []
var blend_shapes := BlendShapeSet.new()

var model_source := ""
var model_name := ""
var base_scale := 1.0
var scale_multiplier := 1.0
var model_stats: Dictionary = {}
var model_warnings: PackedStringArray = []

var _grabs: Array[XRInteractor] = []
var _single_offset_local := Vector3.ZERO
var _single_start_basis := Basis()
var _single_start_interactor_basis := Basis()
var _single_start_scale := 1.0
var _dual_start_distance := 1.0
var _dual_start_scale := 1.0
var _dual_start_rotation := Basis()
var _dual_midpoint_local := Vector3.ZERO
var _dual_start_axis := Vector3.ZERO
var _hovered := false
var _parts: Array[MeshInstance3D] = []
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _history_suspended := false
