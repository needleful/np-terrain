@tool
class_name NPTerrainStamp
extends NPTerrainElement

signal stroke_started(element: NPTerrainStamp)
signal stroke_continued(element: NPTerrainStamp)
signal stroke_finished(element: NPTerrainStamp)

@export var max_height := _range.y:
	set(v):
		_range.y = v
		_notify_movement()
	get: return _range.y
@export var min_height := _range.x:
	set(v):
		_range.x = v
		_notify_movement()
	get: return _range.x
@export var blend_mode := NPTerrain.BlendMode.Mix:
	set(b):
		blend_mode = b
		_notify_movement()

@export var strokes: Array[NPPaintStroke] = []

var composited_stroke := RID()
var original_image := RID()

var _range := Vector2i(-100, 100)

var latest_stroke: NPPaintStroke:
	get: return strokes[strokes.size() - 1]

func _get_format() -> Image.Format:
	return Image.FORMAT_RGF

func stroke_start(stroke: NPPaintStroke):
	strokes.append(stroke)
	stroke_started.emit(self)

func stroke_continue(point: Vector2):
	var s := latest_stroke
	s.points.append(point)
	stroke_continued.emit(self)

func stroke_finish():
	stroke_finished.emit(self)
