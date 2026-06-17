@tool
class_name NiceSlider
extends Control

@export_exp_easing('attenuation') var curve := 1.0

@onready var slider:Slider = $HSlider

var proper_value: float:
	get: return pow(slider.value, curve)

func _ready():
	slider.value_changed.connect(_on_value_changed)

func _on_value_changed(v: float):
	var text: String
	v = proper_value
	if slider.step < 0.1 && abs(v) < 0.1:
		text = '%.6f' % v
	if slider.step < 1:
		text = '%.2f' % v
	else:
		text = '%d' % round(v)
	$Label.text = text
