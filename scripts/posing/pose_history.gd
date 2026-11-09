class_name PoseHistory
extends RefCounted
## In-memory undo/redo stack of full pose documents (same shape as capture_pose()).

const LIMIT := 40

var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var suspended := false


func clear() -> void:
	_undo.clear()
	_redo.clear()


func checkpoint(snapshot: Dictionary) -> void:
	if suspended:
		return
	_undo.append(snapshot)
	while _undo.size() > LIMIT:
		_undo.pop_front()
	_redo.clear()


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func undo_count() -> int:
	return _undo.size()


func redo_count() -> int:
	return _redo.size()


## Returns the snapshot to apply, or {} if none. Caller should pass current as `current`.
func undo(current: Dictionary) -> Dictionary:
	if not can_undo():
		return {}
	_redo.append(current)
	return _undo.pop_back()


func redo(current: Dictionary) -> Dictionary:
	if not can_redo():
		return {}
	_undo.append(current)
	return _redo.pop_back()


func drop_last() -> void:
	if not _undo.is_empty():
		_undo.pop_back()
