@tool
class_name NPPaintStroke
extends Resource

@export_exp_easing('attenuation') var attenuation: float = 1
@export var radius: float = 10.0
@export var color: Color = Color.GREEN
@export var points: PackedVector2Array
@export var blend_mode := NPTerrain.BlendMode.Mix

func set_properties(point: NPPaintPoint, from: Vector2, to: Vector2):
	attenuation = point.attenuation
	radius = point.radius
	color = point.color
	points = [from, to]
