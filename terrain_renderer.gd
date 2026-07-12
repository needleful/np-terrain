@tool
class_name TerrainRenderer

signal render_complete

class CreatedUniform:
	var uniform: RDUniform
	var rids: Array[RID]
	
	func _init(p_uni: RDUniform, p_rids :Array[RID]= []):
		uniform = p_uni
		rids = p_rids

class ShareableTexture:
	var main: RID
	var local: RID
	func _init(p_main: RID, p_local: RID):
		main = p_main
		local = p_local
	
	func free_from(gpu: RenderingDevice):
		if main:
			gpu.free_rid(main)
		if local and local != main:
			gpu.free_rid(local)

var size := Vector2i.ZERO
var input: PackedByteArray
var input_buffer: RID
var input_uniform: RDUniform
# Output for an image2D (r32f)
var heightmap_out: ShareableTexture
# image2D(rg16f)
var normal_out: ShareableTexture
# image2d(r8ui)
var holes_out: ShareableTexture
var collider_out: RID
var attributes_out: Dictionary[StringName, ShareableTexture]

var gpu:RenderingDevice
var main_device: RenderingDevice
var reset_shader: RID
var reset_rgba_shader: RID
var hole_reset_shader: RID
var heightmap_shader: RID
var hole_shader: RID
var normals_shader: RID
var collider_shader: RID
var line_shader: RID
var line_rgba_shader: RID
var stroke_height_shader: RID
var stroke_rgba_shader: RID
var attribute_shader: RID
var convert_shader_rgba_rg: RID

var heightmap_rendering := true
var holes_rendering := true
var submitted := false
var attributes_rendering: Dictionary[StringName, bool] = {}

var resources_to_free: Array[RID]
var result_samplers: Dictionary[RID, CachedSampler]

class CachedSampler:
	var sampler: RID
	var texture: RID
	
	static func data_format_from_image(img: Image) -> RenderingDevice.DataFormat:
		match img.get_format():
			Image.FORMAT_R8:
				return RenderingDevice.DATA_FORMAT_R8_UNORM
			Image.FORMAT_RGB8:
				return RenderingDevice.DATA_FORMAT_R8G8B8_UINT
			Image.FORMAT_RGBA8:
				return RenderingDevice.DATA_FORMAT_R8G8B8A8_UINT
			Image.FORMAT_RF:
				return RenderingDevice.DATA_FORMAT_R32_SFLOAT
			Image.FORMAT_RGF:
				return RenderingDevice.DATA_FORMAT_R32G32_SFLOAT
			Image.FORMAT_RGBF:
				return RenderingDevice.DATA_FORMAT_R32G32B32_SFLOAT
			Image.FORMAT_RGBAF:
				return RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
			_:
				push_error('Unsupported Image.Format format: ', img.get_format())
				print_stack()
				return RenderingDevice.DATA_FORMAT_R8G8B8A8_UINT
	
	static func from_image(p_img: Image, gpu: RenderingDevice) -> CachedSampler:
		var c := CachedSampler.new()
		var fmt := RDTextureFormat.new()
		fmt.width = p_img.get_width()
		fmt.height = p_img.get_height()
		p_img.get_format()
		fmt.format = data_format_from_image(p_img)
		fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		var data := p_img.get_data()
		c.sampler = _create_sampler(gpu)
		c.texture = gpu.texture_create(fmt, RDTextureView.new(), [data])
		if not c.sampler or not c.texture:
			print_debug('Could not convert image: ', p_img.resource_path)
			print_stack()
		return c
	
	static func from_texture_rid(texture: RID, gpu: RenderingDevice) -> CachedSampler:
		var cs := CachedSampler.new()
		cs.texture = texture
		cs.sampler = _create_sampler(gpu)
		return cs
		
	static func _create_sampler(gpu: RenderingDevice):
		var sampler_state := RDSamplerState.new()
		sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
		sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
		sampler_state.mip_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
		return gpu.sampler_create(sampler_state)

var sampler_cache: Dictionary[Image, CachedSampler]
var work_queue: Array[Callable]

func _init(p_gpu: RenderingDevice):
	gpu = p_gpu
	main_device = RenderingServer.get_rendering_device()
	heightmap_rendering = false
	holes_rendering = false
	_load_shaders()

func _load_shaders():
	reset_shader = _load_shader('res://addons/np-terrain/shaders/reset_r32.glsl')
	reset_rgba_shader = _load_shader('res://addons/np-terrain/shaders/reset_rgba.glsl')
	hole_reset_shader = _load_shader('res://addons/np-terrain/shaders/reset_r8.glsl')
	heightmap_shader = _load_shader('res://addons/np-terrain/shaders/image_mix_rg.glsl')
	attribute_shader = _load_shader('res://addons/np-terrain/shaders/image_mix_rgba.glsl')
	normals_shader = _load_shader('res://addons/np-terrain/shaders/make_normals.glsl')
	hole_shader = _load_shader('res://addons/np-terrain/shaders/cut_holes.glsl')
	collider_shader = _load_shader('res://addons/np-terrain/shaders/create_collider.glsl')
	line_shader = _load_shader('res://addons/np-terrain/shaders/line_mix_opacity.glsl')
	stroke_height_shader = _load_shader('res://addons/np-terrain/shaders/stroke_mix_height.glsl')
	stroke_rgba_shader = _load_shader('res://addons/np-terrain/shaders/stroke_mix_rgba.glsl')
	line_rgba_shader = _load_shader('res://addons/np-terrain/shaders/line_mix_rgba.glsl')
	convert_shader_rgba_rg = _load_shader('res://addons/np-terrain/shaders/convert_rgba_rg32.glsl')

func _check_size(output_resolution: Vector2i):
	if size != output_resolution:
		size = output_resolution
		_free_buffers()
		input = PackedByteArray()
		input.resize(8)
		input.encode_u32(0, output_resolution.x)
		input.encode_u32(4, output_resolution.y)
		input_buffer = gpu.storage_buffer_create(input.size(), input)

		heightmap_out = _shared_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT, size)
		normal_out = _shared_texture(RenderingDevice.DATA_FORMAT_R16G16_SFLOAT, size)
		holes_out = _shared_texture(RenderingDevice.DATA_FORMAT_R8_UNORM, size)
		collider_out = _local_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT, size);
		for at in attributes_out:
			attributes_out[at] = _shared_texture(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, output_resolution)

func begin_heightmap(output_resolution: Vector2i):
	heightmap_rendering = true
	work_queue.append(_begin_heightmap.bind(output_resolution))

func _begin_heightmap(output_resolution: Vector2i):
	_check_size(output_resolution)
	_reset(reset_shader, heightmap_out.local)

func begin_holes(output_resolution: Vector2i):
	holes_rendering = true
	work_queue.append(_begin_holes.bind(output_resolution))

func _begin_holes(output_resolution: Vector2i):
	_check_size(output_resolution)
	_reset(hole_reset_shader, holes_out.local)

func attrib_start_render(output_resolution: Vector2i, at: StringName) -> bool:
	if at in attributes_rendering and attributes_rendering[at]:
		return false
	else:
		attributes_rendering[at] = true
		work_queue.append(_attrib_start_render.bind(output_resolution, at))
		return true

func _attrib_start_render(output_resolution: Vector2i, at: StringName):
	_check_size(output_resolution)
	if not at in attributes_out:
		attributes_out[at] = _shared_texture(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, output_resolution)
	_reset(reset_rgba_shader, attributes_out[at].local)

func _end():
	for j in resources_to_free:
		gpu.free_rid(j)
	resources_to_free.clear()
	heightmap_rendering = false
	holes_rendering = false
	attributes_rendering.clear()

func render_stamp(inverse_transform: Transform3D, e: NPTerrainElement):
	work_queue.append(_image_mix.bind(inverse_transform, e))

func begin_path(e: NPTerrainPath) -> bool:
	if not e.path:
		push_warning('Terrain path has no path: ', e.name)
		return false
	elif not e.path_start:
		push_warning('Terrain path has no start properties: ', e.name)
		return false
	elif not e.resolution:
		push_warning('Path has a resolution of zero: ', e.name)
		return false
	work_queue.append(_begin_path.bind(e))
	return true

func _begin_path(e: NPTerrainPath):
	if e.result_image:
		_free_cached(e.result_image)
	if e.converted_result:
		e.converted_result = _free_cached(e.converted_result)
	e.result_size = size*e.resolution
	e.result_image = _local_texture(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, e.result_size)
	_reset(reset_rgba_shader, e.result_image, e.result_size)
	var points := e.path.curve.tessellate()
	var start:NPPaintPoint = e.path_start
	var end: NPPaintPoint
	if e.path_end:
		end = e.path_end
	else:
		end = start
	var stroke := NPPaintStroke.new()
	var stroke2 := NPPaintStroke.new()
	var t := e.global_transform
	var h := e.get_heightmap()
	var inv := h.global_transform.inverse().scaled_local(
		Vector3(e.resolution/h.terrain_scale, 1, e.resolution/h.terrain_scale))
	var hsize := Vector2(e.result_size)/2
	var point_count := points.size() - 1
	if e.debug_point_count >= 0:
		point_count = min(point_count, e.debug_point_count)
	var s := points.size() - 1
	for p in point_count:
		var from := inv*t*points[p]
		var to := inv*t*points[p+1]
		var offset := float(p)/s
		var offset2 := float(p+1)/s
		var properties := start.lerp(end, offset)
		var properties2 := start.lerp(end, offset2)
		if e.mode == NPTerrainPath.Mode.HeightMap:
			properties.color = Color(from.y, 0, 0, properties.color.a)
			properties2.color = Color(to.y, 0, 0, properties2.color.a)
		#print('-- Path: {%s to %s}: %s, %f, %f' % [str(from), str(to), str(properties.color), properties.attenuation, properties.radius])
		var from2 := Vector2(from.x, from.z) + hsize
		var to2 := Vector2(to.x, to.z) + hsize
		stroke.set_properties(properties, from2, to2)
		stroke2.set_properties(properties2, from2, to2)
		_line_mix(e, stroke, stroke2)

func convert_path(e: NPTerrainPath):
	work_queue.append(_convert_path.bind(e))

func _convert_path(e: NPTerrainPath):
	if e.converted_result:
		_free_cached(e.converted_result)
	e.converted_result = _local_texture(RenderingDevice.DATA_FORMAT_R32G32_SFLOAT, e.result_size)
	var rgba := _image_uniform(e.result_image, 0)
	var rg := _image_uniform(e.converted_result, 1)
	var uset := gpu.uniform_set_create([rgba, rg], convert_shader_rgba_rg, 0)
	_add_job(convert_shader_rgba_rg, uset, e.result_size)

func render_heightmap_path(inverse_transform: Transform3D, e: NPTerrainPath):
	work_queue.append(_image_mix.bind(inverse_transform, e))

func render_attribute_path(inverse_transform: Transform3D, e: NPTerrainPath):
	work_queue.append(_image_mix.bind(inverse_transform, e))

func create_stroke_buffers(e: NPTerrainStamp):
	work_queue.append(_create_stroke_buffers.bind(e))

func _create_stroke_buffers(e: NPTerrainStamp):
	# Use result as original image
	if e.result_image:
		if e.original_image and e.original_image != e.result_image:
			gpu.free_rid(e.original_image)
		e.original_image = e.result_image
		e.result_image = RID()
		#print('~ Swapping buffers')
	else:
		e.original_image = RID()
		#print('~ New buffers')
	var result_format: RenderingDevice.DataFormat
	if e is NPAttributeStamp:
		result_format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	else:
		result_format = RenderingDevice.DATA_FORMAT_R32G32_SFLOAT
	if not e.result_image:
		e.result_image = _local_texture(
			result_format,
			e.raw_image.get_size(), e.raw_image.get_data())
	if not e.original_image:
		e.original_image = _local_texture(
			result_format,
			e.raw_image.get_size(), e.raw_image.get_data())

	if e.composited_stroke:
		gpu.free_rid(e.composited_stroke)
	e.composited_stroke = _local_texture(
		RenderingDevice.DATA_FORMAT_R32_SFLOAT,
		e.raw_image.get_size())
	assert(gpu.texture_get_format(e.composited_stroke).format == RenderingDevice.DATA_FORMAT_R32_SFLOAT)

func start_stroke(e: NPTerrainStamp, s: NPPaintStroke):
	work_queue.append(_start_stroke.bind(e,s))

func _start_stroke(e: NPTerrainStamp, s: NPPaintStroke):
	assert(gpu.texture_get_format(e.composited_stroke).format == RenderingDevice.DATA_FORMAT_R32_SFLOAT)
	_reset(reset_shader, e.composited_stroke, e.image.get_size())

func render_stroke_line(e: NPTerrainStamp, s: NPPaintStroke, start_index: int):
	work_queue.append(_line_mix.bind(e, s, s, start_index))

func render_stroke(e: NPTerrainStamp, s: NPPaintStroke):
	work_queue.append(_stroke_mix.bind(e, s))

func render_normals():
	work_queue.append(_build_normals)

func create_colliders(inverse_scale: float):
	work_queue.append(_create_colliders.bind(inverse_scale))

func _create_colliders(inverse_scale: float):
	var u0 := _image_uniform(heightmap_out.local, 0)
	var u1 := _image_uniform(holes_out.local, 1)
	var u2 := _image_uniform(collider_out, 2)
	var bytes := PackedByteArray()
	bytes.resize(16)
	bytes.encode_float(0, NAN)
	bytes.encode_float(4, inverse_scale)
	var uset := gpu.uniform_set_create([u0, u1, u2], collider_shader, 0)
	_add_job(collider_shader, uset, size, bytes)
	resources_to_free.append(uset)

func free_result(e: NPTerrainGroup):
	work_queue.append(_free_result.bind(e))

func _free_result(e: NPTerrainGroup):
	e.result_image = _free_cached(e.result_image)
	if e is NPTerrainPath:
		e.converted_result = _free_cached(e.converted_result)
	if e is NPTerrainStamp:
		if e.composited_stroke:
			gpu.free_rid(e.composited_stroke)
		if e.original_image:
			gpu.free_rid(e.original_image)
		e.composited_stroke = RID()
		e.original_image = RID()

func _free_cached(image :RID):
	if not image:
		return image
	if image in result_samplers:
		gpu.free_rid(result_samplers[image].sampler)
		result_samplers.erase(image)
	gpu.free_rid(image)
	return RID()

func _submit_all():
	#print('- Executing ', work_queue.size(), ' tasks.')
	for c in work_queue:
		#print('-- ', c.get_method())
		c.call()
	work_queue.clear()
	submitted = false
	_end()
	render_complete.emit.call_deferred()

func submit():
	if submitted or work_queue.is_empty():
		return
	submitted = true
	if gpu != main_device:
		_submit_all()
		gpu.submit()
	else:
		RenderingServer.call_on_render_thread(_submit_all)
		RenderingServer.force_sync()

func sync():
	if gpu != main_device:
		gpu.sync()

func get_result() -> PackedByteArray:
	return _get_texture(heightmap_out)

func get_normals() -> PackedByteArray:
	return _get_texture(normal_out)

func get_holes() -> PackedByteArray:
	return _get_texture(holes_out)

func get_collider_data() -> PackedFloat32Array:
	var bytes := gpu.texture_get_data(collider_out, 0)
	return bytes.to_float32_array()

func get_attribute(at: StringName) -> PackedByteArray:
	return _get_texture(attributes_out[at])

func _get_texture(texture: ShareableTexture) -> PackedByteArray:
	return main_device.texture_get_data(texture.main, 0)

func get_local_texture(texture: RID) -> PackedByteArray:
	return gpu.texture_get_data(texture, 0)

static func _make_format(format: RenderingDevice.DataFormat, p_size: Vector2i) -> RDTextureFormat:
	var tf := RDTextureFormat.new()
	tf.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	tf.width = p_size.x
	tf.height = p_size.y
	tf.depth = 1
	tf.mipmaps = 1
	tf.array_layers = 1
	tf.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT |
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)
	tf.format = format
	return tf

func _shared_texture(format: RenderingDevice.DataFormat, p_size: Vector2i) -> ShareableTexture:
	var main: RID
	var local: RID
	if gpu != main_device:
		var tf := _make_format(format, p_size)
		main = main_device.texture_create(tf, RDTextureView.new())
		local = gpu.texture_create_from_extension(
			tf.texture_type, tf.format, tf.samples, tf.usage_bits, 
			main_device.get_driver_resource(RenderingDevice.DRIVER_RESOURCE_TEXTURE, main, 0),
			tf.width, tf.height, tf.depth, tf.array_layers, tf.mipmaps)
	else:
		main = _local_texture(format, p_size)
		local = main
	if main == RID() or local == RID():
		push_error('Could not create texture')
	var s := ShareableTexture.new(main, local)
	return s

func _local_texture(format: RenderingDevice.DataFormat, p_size: Vector2i, bytes: PackedByteArray = []) -> RID:
	var tf := _make_format(format, p_size)
	return gpu.texture_create(tf, RDTextureView.new(), [] if bytes.is_empty() else [bytes])

func _load_shader(file: String) -> RID:
	var shader:RDShaderFile = load(file)
	if !shader:
		push_error('Could not load file: ', file)
		return RID()
	var spirv := shader.get_spirv()
	if !spirv:
		push_error('Could not create bytecode: ', file)
		return RID()
	if spirv.compile_error_compute:
		push_error('Error: ', file, ': ', spirv.compile_error_compute)
	var s := gpu.shader_create_from_spirv(spirv)
	if !s:
		push_error('Could not compile shader: ', file)
	return s
	
func _reset(shader: RID, local_texture: RID, p_size := Vector2i.ZERO) -> void:
	if not p_size:
		p_size = size
	var uniform := _image_uniform(local_texture, 0)
	var uniform_set := gpu.uniform_set_create([uniform], shader, 0)
	_add_job(shader, uniform_set, p_size)
	resources_to_free.append(uniform_set)

# If holes is false (default): blend heightmaps
# Otherwise, blend holes
func _image_mix(inverse_transform: Transform3D, e: NPTerrainGroup) -> void:
	var holes := e is NPTerrainHole
	var matrix: Transform3D
	var shader: RID
	var out_size: Vector2i
	if e is NPTerrainElement:
		out_size = e.image.get_size()
		matrix = (inverse_transform*e.global_transform).affine_inverse()
		if e is NPTerrainHole:
			shader = hole_shader
		elif e is NPAttributeStamp:
			shader = attribute_shader
		elif e is NPTerrainStamp:
			shader = heightmap_shader
	elif e is NPTerrainPath:
		## Already transformed
		var f:float = e.resolution
		matrix = Transform3D.IDENTITY.scaled_local(Vector3(f,1,f))
		out_size = e.result_size
		if e.mode == NPTerrainPath.Mode.HeightMap:
			shader = heightmap_shader
		else:
			shader = attribute_shader
	else:
		push_error('Cannot render element: ', e.name)
		return

	var m : PackedFloat32Array = [
		matrix.basis.x.x, matrix.basis.y.x, matrix.basis.z.x, matrix.origin.x,
		matrix.basis.x.y, matrix.basis.y.y, matrix.basis.z.y, matrix.origin.y,
		matrix.basis.x.z, matrix.basis.y.z, matrix.basis.z.z, matrix.origin.z
	]
	var input_bytes := m.to_byte_array()
	var s := input_bytes.size()
	var common_data_size := 24
	input_bytes.resize(s + common_data_size + 8)
	## Height range
	if e is NPTerrainPath:
		input_bytes.encode_float(s+0, 0)
		input_bytes.encode_float(s+4, 1)
	elif not holes:
		var h := Vector2(e.min_height, e.max_height)
		input_bytes.encode_float(s+0, h.x)
		input_bytes.encode_float(s+4, h.y)

	# TODO: fix get_bounds for free performance
	#var lh := get_bounds(inverse_transform, e)
	#low = lh.low
	#high = lh.high

	var low := -Vector2i(size/2)
	var high := Vector2i(size/2)

	var start_corner:Vector2i = Vector2i(0,0).max(low + size/2)
	var end_corner:Vector2i = size.min(high + size/2)
	var job_size := end_corner - start_corner
	
	var o := input_bytes.size() - common_data_size
	## Image size
	input_bytes.encode_u32(o, out_size.x)
	input_bytes.encode_u32(o+4, out_size.y)
	## Starting corner
	input_bytes.encode_u32(o+8, start_corner.x)
	input_bytes.encode_u32(o+12, start_corner.y)
	if not holes:
		input_bytes.encode_u32(o+16, e.blend_mode)
	
	var buffer:ShareableTexture
	if holes:
		buffer = holes_out
	elif e is NPAttributeStamp:
		buffer = attributes_out[e.attribute]
	elif e is NPTerrainPath:
		if e.mode == NPTerrainPath.Mode.HeightMap:
			buffer = heightmap_out
		else:
			buffer = attributes_out[e.attribute]
	else:
		buffer = heightmap_out

	var source_uni := _buffer_uniform(input_buffer, 0)
	var sampler := _sampler_uniform(e, 1)
	var output_uni := _image_uniform(buffer.local, 2)
	var uset := gpu.uniform_set_create([source_uni, sampler.uniform, output_uni], shader, 0)
	_add_job(shader, uset, job_size, input_bytes)

func _line_mix(e: NPTerrainGroup, stroke_start: NPPaintStroke, stroke_end: NPPaintStroke, start: int = 0) -> void:
	var out_size: Vector2i
	var shader: RID
	var output: RID
	if e is NPTerrainStamp:
		out_size = e.image.get_size()
		shader = line_shader
		output = e.composited_stroke
	elif e is NPTerrainPath:
		out_size = e.result_size
		shader = line_rgba_shader
		output = e.result_image
	else:
		push_error('Cannot render line for this element: ', e.name)
		return
	var from := stroke_start.points[start]
	var to := stroke_start.points[start + 1]

	var push_constants := PackedByteArray()
	push_constants.resize(80)
	#print('::', stroke_start.color.r)
	push_constants.encode_float(0, from.x)
	push_constants.encode_float(4, from.y)
	push_constants.encode_float(8, to.x)
	push_constants.encode_float(12, to.y)
	
	push_constants.encode_float(16, stroke_start.color.r)
	push_constants.encode_float(16+4, stroke_start.color.g)
	push_constants.encode_float(16+8, stroke_start.color.b)
	push_constants.encode_float(16+12, stroke_start.color.a)
	
	push_constants.encode_float(16+16, stroke_start.radius)
	push_constants.encode_float(16+20, stroke_start.attenuation)
	
	push_constants.encode_float(48, stroke_end.color.r)
	push_constants.encode_float(48+4, stroke_end.color.g)
	push_constants.encode_float(48+8, stroke_end.color.b)
	push_constants.encode_float(48+12, stroke_end.color.a)
	
	push_constants.encode_float(48+16, stroke_end.radius)
	push_constants.encode_float(48+20, stroke_end.attenuation)
	
	push_constants.encode_u32(72, out_size.x)
	push_constants.encode_u32(76, out_size.y)
	
	var output_uniform := _image_uniform(output, 0)
	var uset := gpu.uniform_set_create([output_uniform], shader, 0)
	_add_job(shader, uset, out_size, push_constants)

func _stroke_mix(e: NPTerrainStamp, s: NPPaintStroke):
	var shader := stroke_rgba_shader if e is NPAttributeStamp else stroke_height_shader
	var opacity := _image_uniform(e.composited_stroke, 0)
	var source := _image_uniform(e.original_image, 1)
	var target := _image_uniform(e.result_image, 2)
	var push_constants := PackedByteArray()
	push_constants.resize(32)
	push_constants.encode_float(0, s.color.r)
	push_constants.encode_float(4, s.color.g)
	push_constants.encode_float(8, s.color.b)
	push_constants.encode_float(12, s.color.a)
	
	push_constants.encode_u32(16, s.blend_mode)
	var uset := gpu.uniform_set_create([opacity, source, target], shader, 0)
	_add_job(shader, uset, e.image.get_size(), push_constants)

# TODO: this doesn't quite work with our scaled transforms
# The performance gain is unnoticeable in tests, but maybe necessary later?
func get_bounds(inverse_transform: Transform3D, e: NPTerrainElement) -> Dictionary:
	var img_size := e.image.get_size()
	var inv_scale := inverse_transform.basis.get_scale()
	# Calculate the 2D bounds of the image
	var img_up := -e.global_basis.z*(img_size.y/2.0)/inv_scale.z
	var img_right := e.global_basis.x*(img_size.x/2.0)/inv_scale.x
	var corner_u_r := e.global_position + (img_up + img_right)
	var corner_d_r := e.global_position + (-img_up + img_right)
	var corner_u_l := e.global_position + (img_up - img_right)
	var corner_d_l := e.global_position + (-img_up - img_right)
	
	var high := Vector2i(size/2)
	var low := -high
	
	low.x = floor(min(
		min(corner_u_r.x, corner_d_r.x),
		min(corner_u_l.x, corner_d_l.x)))
	low.y = ceil(min(
		min(corner_u_r.z, corner_d_r.z),
		min(corner_u_l.z, corner_d_l.z)))

	high.x = floor(max(
		max(corner_u_r.x, corner_d_r.x),
		max(corner_u_l.x, corner_d_l.x)))
	high.y = ceil(max(
		max(corner_u_r.z, corner_d_r.z),
		max(corner_u_l.z, corner_d_l.z)))
	return {'low': low, 'high': high}

func _build_normals() -> void:
	var u1 := _image_uniform(heightmap_out.local, 0)
	var u2 := _image_uniform(normal_out.local, 1)
	var uset := gpu.uniform_set_create([u1, u2], normals_shader, 0)
	_add_job(normals_shader, uset, size)
	resources_to_free.append(uset)

func _add_job(shader: RID, uniform_set:RID, p_size: Vector2i, push_constant:PackedByteArray = []) -> void:
	var pipeline := gpu.compute_pipeline_create(shader)
	var compute_list := gpu.compute_list_begin()
	gpu.compute_list_bind_compute_pipeline(compute_list, pipeline)
	gpu.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	if !push_constant.is_empty():
		gpu.compute_list_set_push_constant(compute_list, push_constant, push_constant.size())
	@warning_ignore("integer_division")
	gpu.compute_list_dispatch(compute_list, (p_size.x + 7)/8, (p_size.y + 7)/8, 1)
	gpu.compute_list_end()
	resources_to_free.append(pipeline)

func _sampler_uniform(e: NPTerrainGroup, bind: int) -> CreatedUniform:
	var sampler: CachedSampler
	if e is NPTerrainPath and e.converted_result:
		if e.converted_result not in result_samplers:
			result_samplers[e.converted_result] = CachedSampler.from_texture_rid(e.converted_result, gpu)
		sampler = result_samplers[e.converted_result]
	elif e.result_image:
		if e.result_image not in result_samplers:
			result_samplers[e.result_image] = CachedSampler.from_texture_rid(e.result_image, gpu)
		sampler = result_samplers[e.result_image]
	elif e is NPTerrainElement:
		var img:Image = e.raw_image
		if img in sampler_cache:
			sampler = sampler_cache[img]
		else:
			sampler = CachedSampler.from_image(img, gpu)
			sampler_cache[img] = sampler
	if not sampler.sampler or not sampler.texture:
		push_error('Could not create sampler uniform for ', e.name)
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	uniform.binding = bind
	uniform.add_id(sampler.sampler)
	uniform.add_id(sampler.texture)
	return CreatedUniform.new(uniform, [sampler.texture, sampler.sampler])

func _image_uniform(p_image: RID, bind: int) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = bind
	uniform.add_id(p_image)
	return uniform

func _buffer_uniform(p_buffer: RID, bind: int) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = bind
	uniform.add_id(p_buffer)
	return uniform

func destroy():
	_free_buffers()
	_free_shaders()
	if gpu != main_device:
		gpu.free()

func _free_shaders():
	for s in [
		reset_shader, hole_reset_shader, heightmap_shader, 
		hole_shader, normals_shader, collider_shader,
		line_shader, stroke_height_shader, stroke_rgba_shader,
		reset_rgba_shader, attribute_shader,
		convert_shader_rgba_rg
	]:
		if s:
			gpu.free_rid(s)

func _free_buffers():
	for s in sampler_cache:
		var cs := sampler_cache[s]
		gpu.free_rid(cs.texture)
		gpu.free_rid(cs.sampler)
	sampler_cache.clear()
	for s in result_samplers:
		var cs := result_samplers[s]
		gpu.free_rid(cs.sampler)
	result_samplers.clear()
	if heightmap_out:
		heightmap_out.free_from(gpu)
		heightmap_out = null
	if collider_out:
		gpu.free_rid(collider_out)
		collider_out = RID()
	for at in attributes_out:
		attributes_out[at].free_from(gpu)
	attributes_out.clear()
	if holes_out:
		holes_out.free_from(gpu)
		holes_out = null
	if normal_out:
		normal_out.free_from(gpu)
		normal_out = null
	if input_buffer:
		gpu.free_rid(input_buffer)
