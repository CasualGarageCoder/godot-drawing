class_name DrawingApp
extends Node

signal resized()

const RESERVED_BUFFER_NAMES : Array[BrushDefinition.BrushBufferName] = [
	BrushDefinition.BrushBufferName.ROLLBACK, BrushDefinition.BrushBufferName.COMMIT,
	BrushDefinition.BrushBufferName.CANVAS_INFO, BrushDefinition.BrushBufferName.CURSOR_INFO,
	BrushDefinition.BrushBufferName.BRUSH_INFO
]

@export var canvas_size : Vector2i :
	set(value):
		canvas_size = value
		_resize_canvas()

@export var container : Texture2DRD

@export var mixing_canvas_parameter_count : int = 4

@export var rendering_shader_path : String = "res://resources/shaders/compute/render_buffer.glsl"

# Utility class to ease buffer registering
class ShaderBuffer:
	var rid : RID
	var type : RenderingDevice.UniformType
	var size : int
	var cache : PackedByteArray

	func _init(r : RID, t : RenderingDevice.UniformType, s : int, c : PackedByteArray = PackedByteArray()) -> void:
		rid = r
		type = t
		size = s
		cache = c
		if not cache.is_empty():
			assert(cache.size() == s)

	func set_parameter_vi(value : Vector2i) -> void:
		cache.encode_s32(0, value.x)
		cache.encode_s32(4, value.y)

	func set_parameter(idx : int, value : float) -> void:
		var pos : int = idx * 4
		assert(pos < cache.size())
		cache.encode_float(pos, value)

	func copy_parameter(src : int, dst : int) -> void:
		var s : int = src * 4; var d : int = dst * 4
		assert(s < cache.size() and d < cache.size())
		cache[d] = cache[s]
		cache[d + 1] = cache[s + 1]
		cache[d + 2] = cache[s + 2]
		cache[d + 3] = cache[s + 3]

	func set_parameter_v(values : PackedFloat32Array) -> void:
		assert(values.size() <= cache.size() * 4)
		for i : int in range(values.size()):
			cache.encode_float(i * 4, values[i])

	func build_empty_cache() -> void:
		cache = PackedByteArray()
		cache.resize(size)
		cache.fill(0)

	func set_cache(c : PackedByteArray) -> void:
		assert(c.size() == size)
		cache = c

	func clear(rd : RenderingDevice, clearing_buf : PackedByteArray) -> void:
		rd.buffer_update(rid, 0, size, clearing_buf)

	func print_content(count : int) -> void:
		if not cache.is_empty():
			for i : int in range(count):
				print("#%d : %f" % [i , cache.decode_float(i * 4)])

class BrushShader:
	var ios : Array[BrushDefinition.BrushBufferName]
	var shader : RID
	var uniform_set : RID
	var pipeline : RID

	var identifier : String
	var path_to_source : String

	func _init(n : String, p : String, sh : RID, uniforms : Array[BrushDefinition.BrushBufferName]) -> void:
		identifier = n
		path_to_source = p
		ios = uniforms
		shader = sh
		uniform_set = RID()
		pipeline = RID()

class Brush:
	var ready : bool = false
	var buffers_to_clean : Array[BrushDefinition.BrushBufferName] = []
	var stages : Array[BrushShader] = []

@onready var rendering_device : RenderingDevice

@onready var rollback_shader_buffer : ShaderBuffer

@onready var commit_shader_buffer : ShaderBuffer

@onready var final_render_shader_buffer : ShaderBuffer

@onready var canvas_info_buffer : ShaderBuffer

@onready var cursor_info_buffer : ShaderBuffer

## Shared amongst all the brushes. Caped at 128 parameters. The first 8 are foreground and background colors.
@onready var brush_parameters_buffer : ShaderBuffer

@onready var render_shader : RID
@onready var render_uniform_set : RID
@onready var render_pipeline : RID

@onready var buffer_definitions : Dictionary[BrushDefinition.BrushBufferName, int] = {}

@onready var buffers : Dictionary[BrushDefinition.BrushBufferName, ShaderBuffer] = {}

@onready var brushes : Dictionary[String, Brush] = {}

@onready var active_brush : Brush = null

@onready var clearing_buffer : PackedByteArray = PackedByteArray()

func start_draw(brush_name : String, pos : Vector2, velocity : Vector2, tilt : Vector2, pressure : float, t : float) -> void:
	assert(brushes.has(brush_name) and brushes[brush_name].ready)
	active_brush = brushes[brush_name]
	push_cursor_info(pos, velocity, tilt, pressure, t)
	push_cursor_info(pos, velocity, tilt, pressure, t)
	# Clean canvas
	for b : BrushDefinition.BrushBufferName in active_brush.buffers_to_clean:
		buffers[b].clear(rendering_device, clearing_buffer)

func push_cursor_info(pos : Vector2, velocity : Vector2, tilt : Vector2, pressure : float, t : float) -> void:
	# Switch back the former info
	cursor_info_buffer.copy_parameter(8, 0)
	cursor_info_buffer.copy_parameter(9, 1)
	cursor_info_buffer.copy_parameter(10, 2)
	cursor_info_buffer.copy_parameter(11, 3)
	cursor_info_buffer.copy_parameter(12, 4)
	cursor_info_buffer.copy_parameter(13, 5)
	cursor_info_buffer.copy_parameter(14, 6)
	cursor_info_buffer.copy_parameter(15, 7)
	cursor_info_buffer.set_parameter(8 , pos.x)
	cursor_info_buffer.set_parameter(9 , pos.y)
	cursor_info_buffer.set_parameter(10, velocity.x)
	cursor_info_buffer.set_parameter(11, velocity.y)
	cursor_info_buffer.set_parameter(12, tilt.x)
	cursor_info_buffer.set_parameter(13, tilt.y)
	cursor_info_buffer.set_parameter(14, pressure)
	cursor_info_buffer.set_parameter(15, t)

func add_brush(def : BrushDefinition) -> void:
	# Check if the name has not been already taken
	assert(def != null and not brushes.has(def.identifier))
	# Create brush stub
	var brush : Brush = Brush.new()
	# Check buffers definition
	brush.ready = true
	for b : BrushDefinition.BrushBufferName in def.buffers:
		assert(def.buffers[b] > 0)
		if not buffer_definitions.has(b):
			buffer_definitions[b] = def.buffers[b]
			if canvas_size.x == 0 or canvas_size.y == 0:
				brush.ready = false
			else:
				buffers[b] = _create_canvas_buffer(rendering_device, def.buffers[b])
		else:
			assert(def.buffers[b] == buffer_definitions[b])
	for s : BrushStage in def.stages:
		var stage_shader : RID = _init_shader(s.shader)
		var ios : Array[BrushDefinition.BrushBufferName] = []
		var got_all : bool = brush.ready
		for u : BrushDefinition.BrushBufferName in s.buffers:
			got_all = got_all and (u in buffers)
			ios.append(u)
		brush.ready = got_all
		var brush_shader : BrushShader = BrushShader.new(s.name, s.shader, stage_shader, ios)
		if brush.ready:
			_link_brush_shader(brush_shader)
		brush.stages.append(brush_shader)
		for i : BrushDefinition.BrushBufferName in ios:
			if not(i in brush.buffers_to_clean or i in RESERVED_BUFFER_NAMES):
				brush.buffers_to_clean.append(i)
	brushes[def.identifier] = brush

func _set_clearing_buffer_size(sz : int) -> void:
	if sz > (clearing_buffer.size() * 4):
		clearing_buffer.resize(sz * 4)
		for i : int in range(sz):
			clearing_buffer.encode_float(i * 4, NAN) # Really NOT optimal. But better than creating a PackedByteArray EACH TIME

func _link_brush_shader(brush_shader : BrushShader) -> void:
	var uniforms : Array[RDUniform] = []
	for i : int in range(brush_shader.ios.size()):
		_register_uniform_in_set(buffers[brush_shader.ios[i]], i, uniforms)
	brush_shader.uniform_set = rendering_device.uniform_set_create(uniforms, brush_shader.shader, 0)
	brush_shader.pipeline = rendering_device.compute_pipeline_create(brush_shader.shader) # FIXME Can be done ONCE

func _ready() -> void:
	rendering_device = RenderingServer.get_rendering_device() # We must use the main rendering device.
	# First phase
	_init_general_info()
	_init_render_shader()
	# Reset
	_resize_canvas()

func _resize_canvas() -> void:
	if canvas_size.x > 0 and canvas_size.y > 0:
		_reset_canvas_info()
		_initialize_render_stage()
		buffers.clear()
		_restore_built_in_buffers()
		for b : BrushDefinition.BrushBufferName in buffer_definitions:
			buffers[b] = _create_canvas_buffer(rendering_device, buffer_definitions[b])
		for b : String in brushes:
			for s : BrushShader in brushes[b].stages:
				_link_brush_shader(s)
			brushes[b].ready = true
		resized.emit()
		render()
	else:
		# Invalid size
		print("Invalid size %s" % (canvas_size))


func _init_render_shader() -> void:
	render_shader = _init_shader(rendering_shader_path)

func _init_shader(path : String) -> RID:
	var shader_file : RDShaderFile = load(path)
	var shader_spirv : RDShaderSPIRV = shader_file.get_spirv()
	if shader_spirv.compile_error_compute != "":
		push_error(shader_spirv.compile_error_compute)
		assert(false)
	return rendering_device.shader_create_from_spirv(shader_spirv)

func _init_general_info() -> void:
	canvas_info_buffer = _create_uniform_buffer(rendering_device, 4)
	canvas_info_buffer.build_empty_cache()
	# pos_x, pos_y, tilt_x, tilt_y, velocity_x, velocity_y, pressure, time
	# x2 (because of previous state) = 16
	cursor_info_buffer = _create_uniform_buffer(rendering_device, 16)
	cursor_info_buffer.build_empty_cache()
	brush_parameters_buffer = _create_uniform_buffer(rendering_device, 128)
	brush_parameters_buffer.build_empty_cache()

func _restore_built_in_buffers() -> void:
	buffers[BrushDefinition.BrushBufferName.CURSOR_INFO] = cursor_info_buffer
	buffers[BrushDefinition.BrushBufferName.CANVAS_INFO] = canvas_info_buffer
	buffers[BrushDefinition.BrushBufferName.BRUSH_INFO] = brush_parameters_buffer
	buffers[BrushDefinition.BrushBufferName.ROLLBACK] = rollback_shader_buffer
	buffers[BrushDefinition.BrushBufferName.COMMIT] = commit_shader_buffer

func _reset_canvas_info() -> void:
	canvas_info_buffer.set_parameter_vi(canvas_size)
	_update_buffer(rendering_device, canvas_info_buffer)

func _free_buffer(sh : ShaderBuffer) -> void:
	if sh != null and sh.rid.is_valid():
		rendering_device.free_rid(sh)

func _initialize_render_stage() -> void:
	_free_buffer(rollback_shader_buffer)
	_free_buffer(commit_shader_buffer)
	_free_buffer(final_render_shader_buffer)
	_set_clearing_buffer_size(canvas_size.x * canvas_size.y * 4 * mixing_canvas_parameter_count)
	rollback_shader_buffer = _create_storage_buffer(rendering_device, canvas_size.x * canvas_size.y * 4 * mixing_canvas_parameter_count)
	commit_shader_buffer = _create_storage_buffer(rendering_device, canvas_size.x * canvas_size.y * 4 * mixing_canvas_parameter_count)
	final_render_shader_buffer = _create_hires_image_buffer(rendering_device, canvas_size)
	if container != null:
		assert(final_render_shader_buffer.rid.is_valid())
		container.texture_rd_rid = final_render_shader_buffer.rid

	var uniforms : Array[RDUniform] = []
	_register_uniform_in_set(final_render_shader_buffer, 0, uniforms)
	_register_uniform_in_set(commit_shader_buffer, 1, uniforms)
	_register_uniform_in_set(canvas_info_buffer, 2, uniforms)
	_reset_canvas_info()

	if render_uniform_set != null and render_uniform_set.is_valid():
		rendering_device.free_rid(render_uniform_set)
	render_uniform_set = rendering_device.uniform_set_create(uniforms, render_shader, 0)
	assert(render_uniform_set != null and rendering_device.uniform_set_is_valid(render_uniform_set))
	if render_pipeline != null and render_pipeline.is_valid():
		rendering_device.free_rid(render_pipeline)
	render_pipeline = rendering_device.compute_pipeline_create(render_shader) # FIXME Can be done ONCE

func commit() -> void:
	assert(commit_shader_buffer.rid.is_valid() and rollback_shader_buffer.rid.is_valid())
	rendering_device.buffer_copy(commit_shader_buffer.rid, rollback_shader_buffer.rid, 0, 0, canvas_size.x * canvas_size.y * 16)
	active_brush = null

func rollback() -> void:
	assert(commit_shader_buffer.rid.is_valid() and rollback_shader_buffer.rid.is_valid())
	rendering_device.buffer_copy(rollback_shader_buffer.rid, commit_shader_buffer.rid, 0, 0, canvas_size.x * canvas_size.y * 16)
	active_brush = null

func set_brush_parameter(idx : int, value : float) -> void:
	if BrushDefinition.BrushBufferName.BRUSH_INFO in buffers and buffers[BrushDefinition.BrushBufferName.BRUSH_INFO].rid.is_valid():
		buffers[BrushDefinition.BrushBufferName.BRUSH_INFO].set_parameter(idx, value)
		_update_buffer(rendering_device, buffers[BrushDefinition.BrushBufferName.BRUSH_INFO]) # FIXME Perhaps not each time ...

func reset_shaders(_sz : Vector2i) -> bool:
	return false

func diagnosis() -> void:
	var structural_info : PackedByteArray = rendering_device.buffer_get_data(canvas_info_buffer.rid)
	print("Size : %d" % (structural_info.size()))
	var width : int = structural_info.decode_u32(0)
	var height : int = structural_info.decode_u32(4)
	print("Read canvas size = %dx%d" % [width, height])
	print("Brushes :")
	for b : String in brushes:
		print("\t%s" % (b))
		for i : int in range(brushes[b].stages.size()):
			var s : BrushShader = brushes[b].stages[i]
			print("\t\tStage #%d : %s" % [i, s.identifier])
			print("\t\t%s" % (s.path_to_source))
			for io : int in range(s.ios.size()):
				print("\t\t\t#%d : %s" % [io, BrushDefinition.BUFFER_NAMES[s.ios[io]]])
	print("---")

func render() -> void:
	RenderingServer.call_on_render_thread(_run_shader)

func _run_shader() -> void:
	if active_brush != null:
		_update_buffer(rendering_device, cursor_info_buffer)
	if active_brush != null:
		for s : BrushShader in active_brush.stages:
			var list : int = rendering_device.compute_list_begin()
			rendering_device.compute_list_bind_compute_pipeline(list, s.pipeline)
			rendering_device.compute_list_bind_uniform_set(list, s.uniform_set, 0)
			@warning_ignore("integer_division")
			rendering_device.compute_list_dispatch(list, (canvas_size.x / 16) + 1, (canvas_size.y / 16) + 1, 1)
			rendering_device.compute_list_end()
	var render_list : int = rendering_device.compute_list_begin()
	assert(render_pipeline != null and render_pipeline.is_valid())
	rendering_device.compute_list_bind_compute_pipeline(render_list, render_pipeline)
	assert(render_uniform_set != null and render_uniform_set.is_valid())
	rendering_device.compute_list_bind_uniform_set(render_list, render_uniform_set, 0)
	@warning_ignore("integer_division")
	rendering_device.compute_list_dispatch(render_list, (canvas_size.x / 16) + 1, (canvas_size.y / 16) + 1, 1)
	rendering_device.compute_list_end()

func _update_buffer(rd : RenderingDevice, buffer : ShaderBuffer) -> void:
	if not buffer.cache.is_empty():
		rd.buffer_update(buffer.rid, 0, buffer.cache.size(), buffer.cache)

func _fill_buffer(rd : RenderingDevice, buffer : ShaderBuffer, value : float, build_cache : bool = false) -> void:
	var values : PackedFloat32Array = PackedFloat32Array()
	@warning_ignore("integer_division")
	values.resize(buffer.size / 4)
	values.fill(value)
	var byte_buffer : PackedByteArray = values.to_byte_array()
	if build_cache:
		buffer.set_cache(byte_buffer)
	rd.buffer_update(buffer.rid, 0, byte_buffer.size(), byte_buffer)

func _fill_buffer_v(rd : RenderingDevice, buffer : ShaderBuffer, values : Array[float], build_cache : bool = false) -> void:
	assert(values != null and not values.is_empty())
	var array_size : int = values.size()
	var float_buffer : PackedFloat32Array = PackedFloat32Array()
	@warning_ignore("integer_division")
	var count : int = buffer.size / 4
	float_buffer.resize(count)
	var i : int = 0
	while (i + array_size) <= count:
		for j : int in range(array_size):
			float_buffer[i] = values[j]
			i = i + 1
	var byte_buffer : PackedByteArray = float_buffer.to_byte_array()
	if build_cache:
		buffer.set_cache(byte_buffer)
	rd.buffer_update(buffer.rid, 0, byte_buffer.size(), byte_buffer)

func _register_uniform_in_set(buffer : ShaderBuffer, binding : int, uniform_list : Array[RDUniform]) -> void:
	var uniform : RDUniform = RDUniform.new()
	uniform.uniform_type = buffer.type
	uniform.binding = binding
	uniform.add_id(buffer.rid)
	uniform_list.append(uniform)

func _create_hires_image_buffer(rd : RenderingDevice, sz : Vector2i) -> ShaderBuffer:
	var format : RDTextureFormat = RDTextureFormat.new()
	format.width = sz.x
	format.height = sz.y
	format.depth = 1
	format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	format.array_layers = 1
	format.mipmaps = 1
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT + RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT + RenderingDevice.TEXTURE_USAGE_STORAGE_BIT + RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT + RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	var init_data : PackedFloat32Array = PackedFloat32Array()
	init_data.resize(sz.x * sz.y * 4)
	init_data.fill(0.0)
	for i : int in range(sz.x * sz.y):
		var idx : int = i * 4
		init_data[idx + 0] = 1.0
		init_data[idx + 3] = 1.0
	return ShaderBuffer.new(rd.texture_create(format, RDTextureView.new(), [ init_data.to_byte_array() ]), RenderingDevice.UNIFORM_TYPE_IMAGE, sz.x * sz.y * 16)

func _create_uniform_buffer(rd : RenderingDevice, parameters_count : int, bytes : PackedByteArray = PackedByteArray()) -> ShaderBuffer:
	# we count each parameter as a 32bit float. However, we will assume that we align on vec4.
	var rounded_size : int = ceil(parameters_count / 4.0) * 16 # 4 * 32bit components
	return ShaderBuffer.new(rd.uniform_buffer_create(rounded_size, bytes), RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, rounded_size, bytes)

func _create_canvas_buffer(rd : RenderingDevice, parameters_count : int, bytes : PackedByteArray = PackedByteArray()) -> ShaderBuffer:
	var rounded_size : int = ceil(parameters_count / 4.0) * 16 # 4 * 32bit components
	var total_size : int = canvas_size.x * canvas_size.y * rounded_size
	_set_clearing_buffer_size(total_size)
	return ShaderBuffer.new(rd.storage_buffer_create(total_size, bytes), RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, total_size)

func _create_storage_buffer(rd : RenderingDevice, size : int, bytes : PackedByteArray = PackedByteArray()) -> ShaderBuffer:
	return ShaderBuffer.new(rd.storage_buffer_create(size, bytes), RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, size)
