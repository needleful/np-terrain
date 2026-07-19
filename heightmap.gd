@tool
class_name NPHeightMap
extends NPTerrainGroup

@export var output_resolution := Vector2i(4096, 4096):
	set(v):
		output_resolution = v
		_recompute_all()

@export var terrain_scale := 1.0:
	set(v):
		terrain_scale = v
		if not is_inside_tree():
			return
		if has_node('StaticBody3D'):
			$StaticBody3D.scale = Vector3(terrain_scale, terrain_scale, terrain_scale)
		_clear_meshes()
		_add_meshes()
		_recompute_all()

## A set of RGBA images, 32 bits per channel, that will be available to edit.
@export var attributes: Dictionary[StringName, ImageTexture] = {}

@export_group('Meshes', 'mesh_')
@export var mesh_component: Mesh = preload('res://addons/np-terrain/meshes/terrain_64x64_Plane.res'):
	set(m):
		mesh_component = m
		if is_inside_tree():
			for mesh in meshes.get_children():
				mesh.mesh = mesh_component

## Map the attributes to the shader parameters for rendering
@export var mesh_shader_remap: Dictionary[StringName, StringName]

@export var mesh_size: Vector2i = Vector2i(64, 64):
	set(s):
		mesh_size = s
		if is_inside_tree():
			_clear_meshes()
			_add_meshes()

@export var mesh_material: Material

@export_group('Results', 'result_')
@export var result_heightmap: ImageTexture
@export var result_normal_map: ImageTexture
@export var result_hole_map: ImageTexture
@export var result_collider: HeightMapShape3D
@export_tool_button('Save Files') var result_save_changes = _save
@export_tool_button('Redraw') var result_redraw = _recompute_all

@onready var meshes:Node3D

class Elements:
	# NPTerrainStamps and NPTerrainPath
	# They need to be in the same list because they're order-sensitive.
	# One can overlay on top of the other.
	var height_edit: Array[NPTerrainGroup] = []
	var holes: Array[NPTerrainHole] = []
	var others: Array[NPTerrainGroup] = []
	# Like height_edit, these have NPAttributeStamps and NPTerrainPath
	var attributes: Dictionary[StringName, Array] = {}

	func add_attribute_editor(a: NPTerrainGroup):
		if not a.attribute:
			push_error('Element has no attribute: ', a.name)
			return
		elif a.attribute not in attributes:
			attributes[a.attribute] = []
		attributes[a.attribute].append(a)

	func has_attribute(a: StringName) -> bool:
		return a in attributes and not attributes[a].is_empty()

	func get_attribute_editors(a: StringName) -> Array:
		if not a in attributes:
			return []
		else:
			return attributes[a]

var renderer: TerrainRenderer
var heightmap_rd: Texture2DRD
var normals_rd: Texture2DRD
var holes_rd: Texture2DRD
var attributes_rd: Dictionary[StringName, Texture2DRD]

func _enter_tree():
	_update_materials(false)
	if not renderer:
		renderer = TerrainRenderer.new(RenderingServer.get_rendering_device())
	if Engine.is_editor_hint():
		_recompute_all.call_deferred()

func _ready():
	_add_meshes()

func _exit_tree():
	_update_materials(false)
	if renderer:
		var _elem = get_elements()
		for e in _elem.height_edit:
			renderer.free_result(e)
		for at in _elem.attributes:
			for e in _elem.attributes[at]:
				renderer.free_result(e)
		renderer.destroy()
		renderer = null
	heightmap_rd = null
	normals_rd = null
	holes_rd = null

func add_element(t: NPTerrainGroup):
	if t is NPTerrainElement:
		_con(t.save_requested, _save_element)
		_con(t.image_changed, _update_image)

	if t is NPTerrainHole:
		_con(t.redraw_requested, _recompute_holes)
	elif t is NPTerrainStamp:
		if t is NPAttributeStamp:
			_con(t.redraw_requested_attrib, _recompute_attribute)
		else:
			_con(t.redraw_requested, _recompute_heightmap)
		_con(t.stroke_started, _on_stroke_started)
		_con(t.stroke_continued, _on_stroke_continued)
		_con(t.stroke_finished, _on_stroke_finished)
	elif t is NPTerrainPath:
		_con(t.path_changed, _recompute_path)
		_con(t.mode_changed, _recompute_all)

static func _con(s: Signal, c: Callable):
	if not s.is_connected(c):
		s.connect(c)

func remove_element(t: NPTerrainGroup):
	if t is NPTerrainElement:
		t.image_changed.disconnect(_update_image)
		_recompute_all.call_deferred()

	if t is NPTerrainHole:
		t.redraw_requested.disconnect(_recompute_holes)
	elif t is NPTerrainStamp:
		if t is NPAttributeStamp:
			t.redraw_requested_attrib.disconnect(_recompute_attribute)
		else:
			t.redraw_requested.disconnect(_recompute_heightmap)
		t.stroke_started.disconnect(_on_stroke_started)
		t.stroke_continued.disconnect(_on_stroke_continued)
		t.stroke_finished.disconnect(_on_stroke_finished)
	elif t is NPTerrainPath:
		t.path_changed.disconnect(_recompute_path)
		t.mode_changed.disconnect(_recompute_all)

func _output_image(format: Image.Format) -> Image:
	return Image.create(output_resolution.x, output_resolution.y, false, format)

func _resize_images():
	if not result_heightmap:
		result_heightmap = ImageTexture.new()
	if not result_normal_map:
		result_normal_map = ImageTexture.new()
	if not result_hole_map:
		result_hole_map = ImageTexture.new()
	if not result_collider:
		result_collider = HeightMapShape3D.new()
	if Vector2i(result_heightmap.get_size()) != output_resolution:
		result_heightmap.set_image(_output_image(Image.FORMAT_RF))
	if Vector2i(result_normal_map.get_size()) != output_resolution:
		result_normal_map.set_image(_output_image(Image.FORMAT_RGF))
	if Vector2i(result_hole_map.get_size()) != output_resolution:
		result_hole_map.set_image(_output_image(Image.FORMAT_R8))
	for at in attributes:
		if not attributes[at]:
			attributes[at] = ImageTexture.new()
		if Vector2i(attributes[at].get_size()) != output_resolution:
			attributes[at].set_image(_output_image(Image.FORMAT_RGBAF))
	result_collider.map_width = output_resolution.x
	result_collider.map_depth = output_resolution.y

func get_inverse_transform() -> Transform3D:
	return global_transform.scaled(Vector3(terrain_scale, 1, terrain_scale)).affine_inverse()

func _recompute_path(path: NPTerrainPath):
	match path.mode:
		NPTerrainPath.Mode.HeightMap:
			_recompute_heightmap()
		NPTerrainPath.Mode.Attribute:
			if path.attribute:
				_recompute_attribute(path.attribute)

func _recompute_all():
	if _compute_start():
		#print('_recompute_all')
		var _elements := get_elements()
		var inverse_transform = get_inverse_transform()
		for attr in attributes:
			if not _elements.has_attribute(attr):
				continue
			renderer.attrib_start_render(output_resolution, attr)
			_sub_compute_attrib(_elements, inverse_transform, attr)
		_sub_compute_height(_elements, inverse_transform)
		_sub_compute_holes(_elements, inverse_transform)
		_compute_complete.call_deferred()

func _recompute_attribute(attr: StringName):
	#print('Compute ', attr)
	var _e := get_elements()
	if not _e.has_attribute(attr):
		return
	if _compute_start() and renderer.attrib_start_render(output_resolution, attr):
		_sub_compute_attrib(_e, get_inverse_transform(), attr)
		_compute_complete.call_deferred()
	#print('$ Rendered %d items' % _e.get_attribute_editors(attr).size())

func _recompute_heightmap():
	if _compute_start() and not renderer.heightmap_rendering:
		#print('_recompute_heightmap')
		_sub_compute_height(get_elements(), get_inverse_transform())
		_compute_complete.call_deferred()

func _recompute_holes():
	if _compute_start() and not renderer.holes_rendering:
		#print('_recompute_holes')
		_sub_compute_holes(get_elements(), get_inverse_transform())
		_compute_complete.call_deferred()

func _update_image(e: NPTerrainElement):
	renderer.free_result(e)

func _on_stroke_started(e: NPTerrainStamp):
	#print('Stroke started')
	renderer.create_stroke_buffers(e)
	renderer.start_stroke(e, e.latest_stroke)

func _on_stroke_continued(e: NPTerrainStamp):
	var p := e.latest_stroke.points
	renderer.render_stroke_line(e, e.latest_stroke, p.size()-2)
	renderer.render_stroke(e, e.latest_stroke)
	if e is NPAttributeStamp:
		_recompute_attribute(e.attribute)
	else:
		_recompute_heightmap()

func _on_stroke_finished(e: NPTerrainStamp):
	#print('Stroke has %d points' % e.latest_stroke.points.size())
	#renderer.swap_stroke_buffers(e)
	pass

func _sub_compute_height(_elements: Elements, inverse_transform: Transform3D):
	renderer.begin_heightmap(output_resolution)
	for el in _elements.height_edit:
		if el is NPTerrainStamp:
			renderer.render_stamp(inverse_transform, el)
		elif el is NPTerrainPath:
			if renderer.begin_path(el):
				renderer.convert_path(el)
				renderer.render_heightmap_path(get_inverse_transform(), el)
				#print('Drawing path: ', el.name)
	renderer.render_normals()

func _sub_compute_holes(_elements: Elements, inverse_transform: Transform3D):
	renderer.begin_holes(output_resolution)
	for hole in _elements.holes:
		renderer.render_stamp(inverse_transform, hole)
	renderer.create_colliders(1.0/terrain_scale)

func _sub_compute_attrib(_elements: Elements, inverse_transform: Transform3D, attr: StringName):
	for el: NPTerrainGroup in _elements.get_attribute_editors(attr):
		if el is NPAttributeStamp:
			renderer.render_stamp(inverse_transform, el)
		elif el is NPTerrainPath:
			if renderer.begin_path(el):
				renderer.render_attribute_path(get_inverse_transform(), el)
				#print('Drawing path: ', el.name)

func _compute_start() -> bool:
	if not renderer or renderer.submitted:
		return false
	_resize_images()
	return true

func _compute_complete():
	renderer.submit()
	_sync()

func _save_element(e: NPTerrainGroup) -> bool:
	if e is NPTerrainStamp:
		if not e.result_image:
			print('No new image: ', e.name)
			return false
		var bytes := renderer.get_local_texture(e.result_image)
		if bytes.is_empty():
			push_error('Could not save element.')
			return false
		var s: Vector2i = e.image.get_size()
		e.image = Image.create_from_data(s.x, s.y, false, e._get_format(), bytes)
		e.strokes.clear()
		renderer.free_result(e)
		var f := '%s/terrain_stamps' % _get_output_folder()
		if not DirAccess.dir_exists_absolute(f):
			DirAccess.make_dir_recursive_absolute(f)
		var path := '%s/stamp_%s_%d.res' % [f, e.name, hash(e.get_path())]
		var err := ResourceSaver.save(e.image, path)
		if err == OK:
			e.image = ResourceLoader.load(path, 'Image', ResourceLoader.CACHE_MODE_REPLACE)
			print('Saved ', e.name, ' to ', path)
		else:
			push_error('Failed to save ', e.name, ' to ', path)
		return err == OK
	else:
		return false

func _sync():
	if renderer.submitted:
		await renderer.render_complete
	renderer.sync()
	# Read the data
	_update_materials()
	if not Engine.is_editor_hint():
		_save()

func _save():
	# Visuals
	var el := get_elements()
	for s in el.height_edit:
		_save_element(s)
	for h in el.holes:
		_save_element(h)
	for at in el.attributes:
		for s in el.get_attribute_editors(at):
			_save_element(s)
	result_heightmap = _save_image_as(renderer.get_result(), result_heightmap, Image.FORMAT_RF, 'heightmap')
	result_normal_map = _save_image_as(renderer.get_normals(), result_normal_map, Image.FORMAT_RGH, 'normals')
	result_hole_map = _save_image_as(renderer.get_holes(), result_hole_map, Image.FORMAT_R8, 'holes')
	result_collider.map_data = renderer.get_collider_data()
	result_collider = _save_resource(result_collider, 'collider')
	for at in renderer.attributes_out:
		var img := attributes[at]
		attributes[at] = _save_image_as(renderer.get_attribute(at), img, Image.FORMAT_RGBAF, at)
	if has_node('StaticBody3D/CollisionShape3D'):
		$StaticBody3D/CollisionShape3D.shape = result_collider
	_clear_meshes()
	_add_meshes()

func _save_image_as(buffer: PackedByteArray, image: ImageTexture, format: int, p_name: String):
	var it := ImageTexture.create_from_image(
		Image.create_from_data(output_resolution.x, output_resolution.y, false, format, buffer))
	return _save_resource(it, p_name)

func _get_output_folder() -> String:
	return ProjectSettings.get_setting('np_terrain/output', '_npt_output')

func _save_resource(it: Resource, p_name: String):
	var dir := 'res://%s/results' % _get_output_folder()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var path := '%s/%s_%s.res' % [dir, name, p_name]
	ResourceSaver.save(it, path)
	print('Saving to ', path)
	return ResourceLoader.load(path, '', ResourceLoader.CACHE_MODE_REPLACE)

func _clear_meshes():
	for m in meshes.get_children():
		m.queue_free()

func _update_materials(use_rd := true):
	var heightmap: Texture2D
	var normals: Texture2D
	var holes: Texture2D
	print_debug('Update materials: ', ('use RD' if use_rd else 'use Results'))
	if use_rd and renderer.heightmap_out:
		if not heightmap_rd:
			heightmap_rd = Texture2DRD.new()
		heightmap_rd.texture_rd_rid = renderer.heightmap_out.main
		if not normals_rd: 
			normals_rd = Texture2DRD.new()
		normals_rd.texture_rd_rid = renderer.normal_out.main
		if not holes_rd:
			holes_rd = Texture2DRD.new()
		holes_rd.texture_rd_rid = renderer.holes_out.main
		heightmap = heightmap_rd
		normals = normals_rd
		holes = holes_rd
	else:
		heightmap = result_heightmap
		normals = result_normal_map
		holes = result_hole_map
	for at in attributes:
		var texture: Texture2D
		if use_rd:
			if at not in attributes_rd:
				attributes_rd[at] = Texture2DRD.new()
			if at in renderer.attributes_out:
				attributes_rd[at].texture_rd_rid = renderer.attributes_out[at].main
			texture = attributes_rd[at]
		else:
			texture = attributes[at]
		if at in mesh_shader_remap:
			mesh_material.set_shader_parameter(mesh_shader_remap[at], texture)
	mesh_material.set_shader_parameter('inverse_scale', 1.0/terrain_scale)
	mesh_material.set_shader_parameter('heightmap', heightmap)
	mesh_material.set_shader_parameter('normals', normals)
	mesh_material.set_shader_parameter('holes', holes)
	mesh_material.set_shader_parameter('size', output_resolution)
	
func _add_meshes():
	if not has_node('_meshes'):
		meshes = Node3D.new()
		meshes.name = '_meshes'
		add_child(meshes)
	else:
		meshes = $_meshes
	_update_materials()
	var tscale := Vector3(terrain_scale, 1, terrain_scale)
	var size := Vector3(output_resolution.x, 0, output_resolution.y)
	var msize := Vector3(mesh_size.x, 0, mesh_size.y)
	var start := (global_transform.origin - size/2 + msize/2 - Vector3(0.5, 0, 0.5))*tscale
	msize *= tscale
	var mesh_count := output_resolution/mesh_size
	msize.y = output_resolution.x
	for x in mesh_count.x:
		for y in mesh_count.y:
			var p := Vector3(x, 0, y)*msize + start
			var m := MeshInstance3D.new()
			m.mesh = mesh_component
			meshes.add_child(m)
			m.global_position = p
			m.scale = tscale
			m.material_override = mesh_material
			m.custom_aabb = AABB(-msize/2, msize*2)

func get_elements() -> Elements:
	var result := Elements.new()
	_add_element_children(result, self)
	return result

func _add_element_children(result: Elements, node):
	for c:Node in node.get_children():
		if c is NPTerrainElement and not c.enabled:
			continue
		if c is NPAttributeStamp:
			result.add_attribute_editor(c)
		elif c is NPTerrainStamp:
			result.height_edit.append(c)
		elif c is NPTerrainPath and c.visible:
			match c.mode:
				NPTerrainPath.Mode.HeightMap:
					result.height_edit.append(c)
				NPTerrainPath.Mode.Attribute:
					result.add_attribute_editor(c)
		elif c is NPTerrainHole:
			result.holes.append(c)
		elif c is NPTerrainElement:
			result.others.append(c)
		if c is NPTerrainElement or c is NPTerrainGroup or c.is_in_group('npt_group'):
			_add_element_children(result, c)
