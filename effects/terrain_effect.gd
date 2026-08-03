@tool
class_name NPTerrainEffect
extends Node

signal effect_changed
signal reloaded_shader

enum Mode {
	Height,
	Attribute
}

@export_file('*.glsl') var shader_path := '':
	set(sp):
		shader_path = sp
		effect_changed.emit()
@export var mode := Mode.Height:
	set(m):
		mode = m
		effect_changed.emit()
@export var active := true:
	set(a):
		active = a
		effect_changed.emit()
@export var push_constants: Array:
	set(p):
		push_constants = p
		effect_changed.emit()

@export_tool_button('Reload Shader') var reload_shader := _reload_shader

func _enter_tree():
	var p := get_parent()
	if p is not NPHeightMap:
		push_error('Effects can only be children of the height map')
	# TODO: register shader with renderer
	# Add signals and stuff
	p.add_effect.call_deferred(self)

func _exit_tree():
	var p := get_parent()
	if p is NPHeightMap:
		p.remove_effect(self)

func _reload_shader():
	reloaded_shader.emit()
