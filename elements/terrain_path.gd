@tool
class_name NPTerrainPath
extends NPTerrainGroup

signal path_changed(NPTerrainPath)
signal mode_changed(NPTerrainPath)

enum Mode {
	HeightMap,
	Attribute
}

## Properties of the path at the start.
@export var path_start: NPPaintPoint:
	set(p):
		if path_start:
			path_start.changed.disconnect(path_changed.emit)
		if p:
			p.changed.connect(path_changed.emit.bind(self))
		path_start = p
		path_changed.emit()
## Properties of the path at the end.
## If null, it's the same as the start.
## If there's a unique path, it will gradually shift from one to the other
@export var path_end: NPPaintPoint:
	set(p):
		if path_end:
			path_end.changed.disconnect(path_changed.emit)
		if p:
			p.changed.connect(path_changed.emit.bind(self))
		path_end = p
		path_changed.emit()

@export var mode := Mode.HeightMap:
	set(m):
		mode = m
		notify_property_list_changed()
		mode_changed.emit(self)

@export var debug_point_count := -1:
	set(p):
		debug_point_count = p
		path_changed.emit(self)

# Resolution of thing. Should be a fraction of 2.
# Sometimes lower is better!
@export var resolution := 0.25

var blend_mode := NPTerrain.BlendMode.Mix
var attribute: StringName

var result_size := Vector2i(0,0)

var result_image := RID()
var converted_result := RID()

# For hokey inheritance reasons, the path can be separate from the NPTerrainPath
var path: Path3D

func _ready():
	var s = self
	if s is Path3D:
		path = s
	else:
		var p := get_parent()
		if p and p is Path3D:
			if not p.is_in_group('npt_group'):
				p.add_to_group('npt_group')
			path = p
		else:
			push_error('Node is not a Path3D and does not have one as a parent: ', name)
	if path:
		path.curve_changed.connect(path_changed.emit.bind(self))
	_add_to_heightmap()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED or what == NOTIFICATION_VISIBILITY_CHANGED:
		path_changed.emit(self)

func _get_property_list() -> Array[Dictionary]:
	var flag := PROPERTY_USAGE_STORAGE
	if mode == Mode.Attribute:
		flag |= PROPERTY_USAGE_EDITOR
	return [
		{
			'name': 'attribute',
			'type': TYPE_STRING_NAME,
			'usage': flag
		},
		{
			'name': 'blend_mode',
			'type': TYPE_INT,
			'hint': PROPERTY_HINT_ENUM,
			'hint_string': ','.join(NPTerrain.BlendMode.keys()),
			'usage': flag
		}
	]
