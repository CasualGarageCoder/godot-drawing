class_name NumberSlider
extends VBoxContainer

signal value_changed(f : float)

@export var value : float = 0.0 : set = submit_value

@export var min_value : float = 0.0 : set = slider_set_min, get = slider_get_min

@export var max_value : float = 0.1 : set = slider_set_max, get = slider_get_max

@export var step_value : float : set = slider_set_step

@export var min_step : float = 0.001

@onready var edit : LineEdit = $Edit

@onready var slider : HSlider = $Slider

@onready var is_dragging : bool = false

func _ready() -> void:
	slider.value_changed.connect(slider_value_changed)
	slider.drag_started.connect(func(): is_dragging = true)
	slider.drag_ended.connect(func(_v) : is_dragging = false)
	edit.text_submitted.connect(submit_text)
	edit.focus_exited.connect(func() : submit_text(edit.text))
	slider_set_min(min_value)
	slider_set_max(max_value)
	submit_value(value)
	step_value = slider.step

func submit_text(t : String) -> void:
	if not is_node_ready():
		return
	if not is_dragging:
		var f : float = t.to_float()
		f = clamp(f, min_value, max_value)
		submit_value(f)

func submit_value(f : float) -> void:
	value = f
	if not is_node_ready():
		return
	slider.value = f
	edit.text = str(f)
	value_changed.emit(f)

func slider_set_step(v : float) -> void:
	if not is_node_ready():
		return
	slider.step = v

func slider_value_changed(v : float) -> void:
	if not is_node_ready():
		return
	edit.text = str(v)
	value_changed.emit(v)

func compute_slider_step() -> void:
	if is_node_ready():
		slider_set_step(min(min_step, (max_value - min_value) / size.x))

func slider_set_min(v : float) -> void:
	min_value = v
	if v > max_value:
		slider_set_max(v)
	else:
		if is_node_ready():
			slider.min_value = v
		compute_slider_step()

func slider_get_min() -> float:
	return min_value

func slider_set_max(v : float) -> void:
	max_value = v
	if v < min_value:
		slider_set_min(v)
	else:
		if is_node_ready():
			slider.max_value = v
		compute_slider_step()

func slider_get_max() -> float:
	return max_value
