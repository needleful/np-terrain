@tool
class_name NPTerrainElement
extends NPTerrainGroup

signal redraw_requested
signal save_requested
signal image_changed(NPTerrainElement)

@export var image: Image:
	set(v):
		image = v
		if image:
			_convert_raw()
		else:
			raw_image = null
		image_changed.emit(self)
		_notify_movement()

@export var size := Vector2i(256, 256)
@export var enabled := true:
	set(t):
		enabled = t
		_notify_movement()

var raw_image: Image
var result_image := RID()

func _notification(what: int):
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_notify_movement()

func _notify_movement():
	redraw_requested.emit()

func _enter_tree() -> void:
	if not image:
		image = _blank_image()
	_convert_raw()
	_add_to_heightmap()

func _exit_tree() -> void:
	var p := get_parent()
	if p is NPHeightMap:
		p.remove_element(self)

func _get_format() -> Image.Format:
	return Image.FORMAT_RGBAF

func _convert_raw():
	if not image:
		raw_image = _blank_image()
	else:
		raw_image = image.duplicate()
		raw_image.convert(_get_format())

func _blank_image() -> Image:
	size = size.max(Vector2i(1,1))
	print('Creating image of size ', size, ' for ', name)
	return Image.create(size.x, size.y, false, _get_format())

func request_save():
	save_requested.emit(self)
