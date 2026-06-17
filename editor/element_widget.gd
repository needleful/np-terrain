@tool
class_name NPTElementWidget
extends Control

signal color_changed
signal radius_changed
signal editing_changed

@export var color_picker: ColorPickerButton
@export var radius_slider: NiceSlider
@export var falloff_slider: NiceSlider
@onready var menu: MenuButton = $MenuButton
@onready var edit_button: CheckButton = $editing
@onready var edit_menu: Button = $EditMenu
@onready var edit_popup: PopupPanel = $EditMenu/EditPanel
@onready var raw_blend_mode: OptionButton = $EditMenu/EditPanel/VBoxContainer/raw_blend_mode
var active_element: NPTerrainGroup
var editing: bool:
	get: return active_element is NPTerrainElement and edit_button.button_pressed
	set(b): edit_button.button_pressed = b

var paint_radius: float:
	get: return radius_slider.proper_value
var paint_color: Color:
	get: return color_picker.color
var paint_falloff: float:
	get: return falloff_slider.proper_value
var paint_blend_mode: NPTerrain.BlendMode:
	get: return clamp(raw_blend_mode.selected, 0, NPTerrain.BlendMode.size())

enum Action {
	SaveStamp,
	RedrawAll,
	SaveAll
}

func _ready():
	var p := menu.get_popup()
	p.id_pressed.connect(_on_action_pressed)
	edit_button.toggled.connect(_on_edit_toggled)
	edit_menu.pressed.connect(_on_edit_menu_pressed)
	edit_popup.hide()
	
	color_picker.color_changed.connect(_on_color_changed)
	radius_slider.slider.value_changed.connect(_on_radius_changed)
	_on_edit_toggled(edit_button.button_pressed)

func set_element(npt: NPTerrainGroup):
	active_element = npt
	if not active_element:
		hide()
		return
	else:
		show()
		var is_elem := active_element is NPTerrainElement and active_element is not NPTerrainPath
		menu['popup/item_0/disabled'] = not is_elem

		edit_button.disabled = not is_elem
		_on_edit_toggled(is_elem and edit_button.button_pressed)

		if active_element is NPTerrainStamp:
			menu.text = 'Terrain Stamp'
		elif active_element is NPTerrainPath:
			menu.text = 'Terrain Path'
		elif active_element is NPTerrainHole:
			menu.text = 'Terrain Hole'
		else:
			menu.text = 'Terrain Group'

func _on_color_changed(c):
	color_changed.emit()

func _on_radius_changed(r):
	radius_changed.emit()

func _on_edit_toggled(v: bool):
	edit_menu.disabled = not v
	editing_changed.emit()

func _on_edit_menu_pressed():
	var w := get_window().position
	edit_popup.position = Vector2(w) + edit_menu.global_position + Vector2(0, edit_menu.size.y)
	edit_popup.popup()

func _on_action_pressed(id: int):
	match id:
		Action.SaveStamp:
			if active_element is NPTerrainElement:
				active_element.request_save()
		Action.RedrawAll:
			if active_element:
				var h := active_element.get_heightmap()
				if h:
					h._recompute_all()
				else:
					push_warning('No heightmap as a parent of this object!')
		Action.SaveAll:
			if active_element:
				var h := active_element.get_heightmap()
				if h:
					h._save()
				else:
					push_warning('No heightmap as a parent of this object!')
				
