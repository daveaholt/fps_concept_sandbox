extends Control

var _entity: Node = null
var _prompt: String = ""

@onready var _crosshair: Control = $Crosshair
@onready var _weapon_label: Label = $Bottom/WeaponLabel
@onready var _health_label: Label = $Bottom/HealthLabel
@onready var _draw_bar: ProgressBar = $Bottom/DrawBar
@onready var _prompt_label: Label = $PromptLabel


func _ready() -> void:
	EventBus.possession_changed.connect(_on_possession_changed)
	EventBus.interaction_prompt.connect(_on_prompt)
	_on_possession_changed(GameClient.my_entity)


func _on_possession_changed(entity: Node) -> void:
	_entity = entity
	visible = entity != null


func _on_prompt(text: String) -> void:
	_prompt = text
	_prompt_label.text = text
	_prompt_label.visible = text != ""


func _process(_delta: float) -> void:
	if _entity == null or not is_instance_valid(_entity):
		visible = false
		return

	visible = true
	var state: InfantryState = _entity.state
	_health_label.text = "HP %d" % roundi(state.health)

	var weapon: WeaponDef = _entity.get_active_weapon()
	var slot := state.weapon_index + 1
	_weapon_label.text = "%d · %s" % [slot, weapon.display_name] if weapon != null else "—"

	var drawing := state.switch_progress < 1.0
	_draw_bar.visible = drawing
	_draw_bar.value = state.switch_progress * 100.0
	_crosshair.modulate.a = 0.35 if drawing else 1.0
