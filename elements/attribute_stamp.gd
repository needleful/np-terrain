@tool
class_name NPAttributeStamp
extends NPTerrainStamp

signal redraw_requested_attrib(attrib: StringName)

# TODO: make a dropdown based on available attributes
@export var attribute: StringName

func _get_format() -> Image.Format:
	return Image.FORMAT_RGBAF

func _notify_movement():
	super._notify_movement()
	redraw_requested_attrib.emit(attribute)
