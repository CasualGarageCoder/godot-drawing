extends Control

const META_VALUE_SLIDERS := "value_sliders"

@export var brushes : Array[BrushTool]

@export var pressure_adjustment : Curve

@onready var drawing_app : DrawingApp = $DrawApp

@onready var render_area : TextureRect = $%RenderArea

@onready var foreground_color_selector : ColorPickerButton = $%ForegroundColorPicker
@onready var background_color_selector : ColorPickerButton = $%BackgroundColorPicker

@onready var tool_icon_container : GridContainer = $%ToolsContainer
@onready var parameters_container : MarginContainer = $%ParametersContainer

@onready var number_slider_instancier := preload("res://scenes/ui/NumberSlider.tscn")

@onready var selected_tool : String = ""

@onready var cursor_drag : bool = false
@onready var current_color : Color

@onready var draw_init : bool = false

@onready var last_position : Vector2
@onready var last_velocity : Vector2
@onready var last_tilt : Vector2
@onready var last_pressure : float
@onready var last_time : float

@onready var current_time : float = 0.0

func _ready() -> void:
	drawing_app.container = ($%RenderArea.texture as Texture2DRD)
	drawing_app.canvas_size = $%RenderArea.size
	$%RenderArea.resized.connect(_on_canvas_resize)

	# Register all declared brushes
	var definitions : Array[DrawingApp.BrushDefinition] = []
	for b in brushes:
		# Inject brush definition
		var new_button : TextureButton = TextureButton.new()
		new_button.name = b.name
		new_button.texture_normal = b.icon

		tool_icon_container.add_child(new_button)

		var parameters_panel := Panel.new()
		parameters_panel.name = b.name
		var parameters_grid := GridContainer.new()
		parameters_panel.add_child(parameters_grid)
		parameters_grid.set_anchors_preset(Control.PRESET_FULL_RECT)
		parameters_grid.columns = 2

		var values : Array[NumberSlider] = []
		for i in range(b.parameters.size()):
			var p := b.parameters[i]
			var parameter_name := Label.new()
			parameter_name.name = p.name
			parameter_name.text = p.name
			parameters_grid.add_child(parameter_name)
			var parameter_input : NumberSlider = number_slider_instancier.instantiate()
			parameter_input.size_flags_horizontal = SizeFlags.SIZE_EXPAND_FILL
			parameter_input.min_value = p.min_value
			parameter_input.max_value = p.max_value
			parameter_input.value = p.default_value
			parameter_input.value_changed.connect(_set_brush_parameter_value.bind(i+4))
			values.append(parameter_input)
			parameters_grid.add_child(parameter_input)

		parameters_container.add_child(parameters_panel)
		parameters_panel.visible = false
		parameters_panel.set_meta(META_VALUE_SLIDERS, values)

		# Create the brush definition.
		var brush_definition : DrawingApp.BrushDefinition = DrawingApp.BrushDefinition.new()
		brush_definition.identifier = b.name
		brush_definition.buffers = {}
		for buf in b.buffers:
			var buffer_name := BrushTool.BUFFER_NAMES[buf]
			brush_definition.buffers[buffer_name] = b.buffers[buf]
		brush_definition.stages = []
		for stage in b.stages:
			var s_dict : Dictionary = {}
			s_dict["source"] = stage.shader
			s_dict["uniforms"] = stage.buffers.map(func(x) : return BrushTool.BUFFER_NAMES[x])
			brush_definition.stages.append(s_dict)
		definitions.append(brush_definition)

		new_button.pressed.connect(_display_parameter_panel.bind(parameters_panel))

	foreground_color_selector.color_changed.connect(_change_brush_color)
	_add_brushes(definitions)

	render_area.gui_input.connect(_on_render_area_input)

func _add_brushes(bs : Array[DrawingApp.BrushDefinition]) -> void:
	for b in bs:
		drawing_app.add_brush(b)
	drawing_app.diagnosis()

func _set_brush_parameter_value(value : float, id : int) -> void:
	drawing_app.set_brush_parameter(id, value)

func _display_parameter_panel(panel : Panel) -> void:
	selected_tool = panel.name
	for c in parameters_container.get_children():
		c.visible = false
	panel.visible = true
	_change_brush_color(foreground_color_selector.color)
	var sliders : Array = panel.get_meta(META_VALUE_SLIDERS, [])
	for i in range(sliders.size()):
		var slider := (sliders[i] as NumberSlider)
		drawing_app.set_brush_parameter(i + 4, slider.value)

func _change_brush_color(color : Color) -> void:
	drawing_app.set_brush_parameter(0, color.r)
	drawing_app.set_brush_parameter(1, color.g)
	drawing_app.set_brush_parameter(2, color.b)
	drawing_app.set_brush_parameter(3, color.a)

func _on_canvas_resize() -> void:
	drawing_app.canvas_size = $%RenderArea.size

func _process(delta : float) -> void:
	current_time += delta
	if cursor_drag:
		drawing_app.render()

func _on_render_area_input(event : InputEvent) -> void:
	if event is InputEventMouseButton:
		var mev := event as InputEventMouseButton
		if mev.button_index == MOUSE_BUTTON_LEFT:
			if (not cursor_drag) and mev.pressed and (not selected_tool.is_empty()):
				cursor_drag = true
				drawing_app.start_draw(selected_tool, mev.position, Vector2.ZERO, Vector2.ZERO, pressure_adjustment.sample_baked(0.), current_time)
			elif cursor_drag and not mev.pressed:
				cursor_drag = false
				drawing_app.commit()
				drawing_app.render()
	elif event is InputEventMouseMotion:
		var mev := event as InputEventMouseMotion
		if cursor_drag:
			drawing_app.push_cursor_info(mev.position, mev.velocity, mev.tilt, pressure_adjustment.sample_baked(mev.pressure), current_time)
