extends Control

const HEADLINE := "KILLED IN ACTION"
const HEADLINE_COLOUR := Color(1.0, 0.45, 0.4)

var _label: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	_label = Label.new()
	_label.name = "Headline"
	_label.set_anchors_preset(Control.PRESET_CENTER)
	_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_label.position = Vector2(0.0, -120.0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.text = HEADLINE
	_label.add_theme_font_size_override("font_size", 46)
	_label.add_theme_color_override("font_color", HEADLINE_COLOUR)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 8)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

	set_process(true)


func _process(_delta: float) -> void:
	visible = GameClient.in_death_cam()
