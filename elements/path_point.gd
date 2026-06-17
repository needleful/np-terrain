@tool
class_name NPPaintPoint
extends Resource

@export_exp_easing('attenuation') var attenuation: float = 1:
	set(a):
		attenuation = a
		changed.emit()
@export var radius: float = 10.0:
	set(a):
		radius = a
		changed.emit()
@export var color: Color = Color.GREEN:
	set(a):
		color = a
		changed.emit()

func lerp(rhs: NPPaintPoint, w: float) -> NPPaintPoint:
	var p := NPPaintPoint.new()
	p.attenuation = lerp(attenuation, rhs.attenuation, w)
	p.radius = lerp(radius, rhs.radius, w)
	p.color = lerp(color, rhs.color, w)
	#print(p.color)
	return p
