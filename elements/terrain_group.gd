# A node that groups terrain elements without doing anything.
# Equivalent to a layer group in an image editor.
@tool
class_name NPTerrainGroup
extends Node3D

func get_heightmap() -> NPHeightMap:
	var p: Node = self
	while p:
		if p is NPHeightMap:
			return p
		p = p.get_parent()
	return null

func _add_to_heightmap():
	set_notify_transform(Engine.is_editor_hint())
	var p := get_heightmap()
	if p is NPHeightMap:
		p.add_element.call_deferred(self)
	else:
		push_error('NP-Terrain: %s does not have an NPHeightMap as a parent' % name)
