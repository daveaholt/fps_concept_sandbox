extends Control

var _entity: Node = null

@onready var _crosshair: Control = $Crosshair
@onready var _weapon_label: Label = $Bottom/WeaponLabel
@onready var _health_label: Label = $Bottom/HealthLabel
@onready var _draw_bar: ProgressBar = $Bottom/DrawBar
@onready var _prompt_label: Label = $PromptLabel


func _ready() -> void:
	EventBus.possession_changed.connect(_on_possession_changed)
	EventBus.interaction_prompt.connect(_on_prompt)
	EventBus.deploy_map_toggled.connect(_on_deploy_map)
	_on_possession_changed(GameClient.my_entity)


func _on_possession_changed(entity: Node) -> void:
	_entity = entity
	visible = entity != null


func _on_deploy_map(open: bool) -> void:
	visible = not open and _entity != null


func _on_prompt(text: String) -> void:
	_prompt_label.text = text
	_prompt_label.visible = text != ""


func _process(_delta: float) -> void:
	if _entity == null or not is_instance_valid(_entity):
		visible = false
		return
	if GameClient.deploy_map_open:
		visible = false
		return

	visible = true
	if _entity.is_in_group("helicopter"):
		_helicopter_panel()
	elif _entity.is_in_group("vehicle"):
		_vehicle_panel()
	else:
		_infantry_panel()


func _infantry_panel() -> void:
	var state: InfantryState = _entity.state
	_health_label.text = "HP %d" % roundi(state.health)

	var weapon: WeaponDef = _entity.get_active_weapon()
	var slot := state.weapon_index + 1
	_weapon_label.text = "%d · %s" % [slot, weapon.display_name] if weapon != null else "—"

	var drawing := state.switch_progress < 1.0
	_draw_bar.visible = drawing
	_draw_bar.value = state.switch_progress * 100.0
	_crosshair.modulate.a = 0.35 if drawing else 1.0


func _helicopter_panel() -> void:
	_health_label.text = "%s   %.0f km/h   %.0f m AGL   %+.1f m/s" % [
		_entity.get_display_name(), _entity.speed_kmh(),
		_entity.altitude_agl(), _entity.climb_rate()]

	var rotor: float = _entity.rotor_fraction()
	var refusal: String = _entity.exit_refusal()
	if refusal != "":
		_weapon_label.text = refusal
	elif _entity.can_hover():
		_weapon_label.text = "Rotor %.0f%%   Collective %.0f%%   F — exit" % [
			rotor * 100.0, _entity.collective_fraction() * 100.0]
	else:
		_weapon_label.text = "Rotor %.0f%% — spooling" % (rotor * 100.0)

	_draw_bar.visible = true
	_draw_bar.value = _entity.collective_fraction() * 100.0
	_crosshair.modulate.a = 0.0


func _vehicle_panel() -> void:
	_health_label.text = "%s   %.0f km/h" % [_entity.get_display_name(), _entity.speed_kmh()]

	var reload: float = _entity.reload_fraction()
	_weapon_label.text = "Cannon ready — LMB" if reload >= 1.0 else "Reloading"
	_draw_bar.visible = reload < 1.0
	_draw_bar.value = reload * 100.0

	var turret: Vector2 = _entity.turret_angles()
	_crosshair.modulate.a = 1.0 if absf(turret.x) < 0.05 else 0.5
