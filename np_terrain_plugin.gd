@tool
class_name NPTerrain
extends EditorPlugin

enum BlendMode {
	Mix,
	Add,
	Min,
	Max,
	Erase,
	Subtract
}

var box_mesh := BoxMesh.new()
var paint_mesh := BoxMesh.new()
var element_box_material := preload("res://addons/np-terrain/editor/element_box.material")
var paint_preview_material := preload("res://addons/np-terrain/editor/paint_preview.material")
var ewidget_template := preload('res://addons/np-terrain/editor/element_widget.tscn')

var preview_box: MeshInstance3D
var preview_paint: MeshInstance3D
var element_widget: NPTElementWidget

var active_object: Node3D
var paint_2d_position: Vector2i
var world_camera: Camera3D

func _enable_plugin() -> void:
	box_mesh.size = Vector3(1,1,1)
	box_mesh.material = element_box_material
	paint_mesh.material = paint_preview_material
	_create_meshes()
	_create_widget()

func _create_widget():
	if element_widget:
		return
	element_widget = ewidget_template.instantiate()
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, element_widget)
	element_widget.hide()
	element_widget.radius_changed.connect(_update_radius)
	element_widget.editing_changed.connect(_on_editing_changed)

func _disable_plugin() -> void:
	preview_box = _destroy(preview_box)
	element_widget = _destroy(element_widget)
	preview_paint = _destroy(preview_paint)

func _handles(object: Object) -> bool:
	return element_widget and object is NPTerrainGroup

func _edit(object):
	if not element_widget:
		_enable_plugin()
		push_warning('Wait, dumbass engine')
	active_object = object as Node3D
	track(active_object)

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent):
	# Not ready
	if not element_widget:
		return false
	if !is_instance_valid(active_object) or !element_widget.editing:
		return false
	if event is InputEventMouse:
		return paint(camera, event)
	return false

func _create_meshes():
	if not is_instance_valid(preview_box):
		preview_box = MeshInstance3D.new()
		preview_box.mesh = box_mesh
	if not is_instance_valid(preview_paint):
		preview_paint = MeshInstance3D.new()
		preview_paint.mesh = paint_mesh

func paint(camera: Camera3D, event: InputEventMouse) -> bool:
	drag_preview_position(camera, event.position)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.is_pressed():
			start_stroke(localize_paint_position(preview_paint.global_position))
		elif event.is_released():
			add_stroke_point(localize_paint_position(preview_paint.global_position))
			finish_stroke()
		return true
	elif event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		var nppos := local_paint_position(event.position)
		add_stroke_point(nppos)
		return true
	return false

func start_stroke(start: Vector2):
	if active_object is NPTerrainStamp:
		var size:Vector2i = active_object.image.get_size()
		start += Vector2(size)/2
		var s := NPPaintStroke.new()
		s.points.append(start)
		s.radius = element_widget.paint_radius
		s.attenuation = element_widget.paint_falloff
		s.color = element_widget.paint_color
		s.blend_mode = element_widget.paint_blend_mode
		active_object.stroke_start(s)

func add_stroke_point(next: Vector2):
	if active_object is NPTerrainStamp and active_object.strokes.size() > 0:
		var s:Vector2i = active_object.image.get_size()
		next += Vector2(s)/2
		var p: PackedVector2Array = active_object.latest_stroke.points
		var l := p[p.size() - 1]
		if next != l:
			active_object.stroke_continue(next)

func finish_stroke():
	if active_object is NPTerrainStamp and active_object.strokes.size() > 0:
		active_object.stroke_finish()

func drag_preview_position(camera: Camera3D, m_pos: Vector2):
	world_camera = camera
	paint_2d_position = m_pos
	preview_paint.show()
	_update_preview_position()

func _on_editing_changed():
	preview_paint.visible = active_object and element_widget.editing

func _update_preview_position():
	if not is_instance_valid(world_camera) or not world_camera.is_inside_tree():
		return
	preview_paint.global_position = global_paint_position(paint_2d_position)
	_update_radius()

func global_paint_position(screen_pos: Vector2) -> Vector3:
	return _zero_intersection(screen_pos)

# Intersection of a line from the screen to the zero plane
# An OK approximation for map painting, for now
func _zero_intersection(screen_pos: Vector2) -> Vector3:
	var position := world_camera.global_position
	var dir := world_camera.project_ray_normal(screen_pos)
	# Not looking at the terrain
	if position.y * dir.y >= 0:
		return position + dir*world_camera.far*0.25
	var slope := position.y/dir.y
	return position - dir*slope

func local_paint_position(screen_pos: Vector2) -> Vector2:
	return localize_paint_position(global_paint_position(screen_pos))

func localize_paint_position(world_pos: Vector3) -> Vector2:
	var invt := active_object.global_transform.affine_inverse()
	var p := invt*world_pos
	return Vector2(p.x, p.z)

func _update_radius():
	preview_paint.scale = 2*Vector3(element_widget.paint_radius, 5000, element_widget.paint_radius)

func track(n: Node3D):
	_create_meshes()
	if n:
		preview_box.show()
		_reparent(preview_box, n)
		_reparent(preview_paint, n)
		if n is NPTerrainElement and n.image:
			var size:Vector2i = n.image.get_size()
			preview_box.scale = Vector3(size.x, 10000, size.y)
	else:
		preview_box.hide()
		preview_paint.hide()
	element_widget.set_element(n as NPTerrainGroup)
	_on_editing_changed()

func _reparent(child: Node3D, parent: Node3D):
	if child.get_parent():
		child.get_parent().remove_child(child)
	parent.add_child(child)
	child.transform = Transform3D()

static func _destroy(object):
	if is_instance_valid(object):
		object.queue_free()
	return null
