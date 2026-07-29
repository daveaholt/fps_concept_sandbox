extends Control

var _entity: Node = null

@onready var _crosshair: Control = $Crosshair
@onready var _weapon_label: Label = $Bottom/WeaponLabel
@onready var _health_label: Label = $Bottom/HealthLabel
@onready var _draw_bar: ProgressBar = $Bottom/DrawBar
@onready var _prompt_label: Label = $PromptLabel

var _squad_label: Label
var _ticket_label: Label
var _result_label: Label


func _ready() -> void:
	_squad_label = Label.new()
	_squad_label.name = "SquadLabel"
	_squad_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_squad_label.position = Vector2(18.0, 14.0)
	add_child(_squad_label)
	_ticket_label = Label.new()
	_ticket_label.name = "TicketLabel"
	_ticket_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_ticket_label.position = Vector2(18.0, 36.0)
	add_child(_ticket_label)

	_result_label = Label.new()
	_result_label.name = "ResultLabel"
	_result_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_result_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_result_label.position = Vector2(0.0, 120.0)
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.visible = false
	add_child(_result_label)

	EventBus.roster_changed.connect(_refresh_squad)
	_refresh_squad()
	EventBus.possession_changed.connect(_on_possession_changed)
	EventBus.interaction_prompt.connect(_on_prompt)
	EventBus.deploy_map_toggled.connect(_on_deploy_map)
	_on_possession_changed(GameClient.my_entity)


func _refresh_squad() -> void:
	var slot := GameClient.my_slot()
	if slot < 0:
		_squad_label.text = "no squad"
		_squad_label.add_theme_color_override("font_color", Color(0.6, 0.62, 0.66))
		_refresh_tickets()
		return
	var squad := Roster.squad_of_slot(slot)
	_squad_label.text = "TEAM %d  ·  %s SQUAD" % [Roster.team_of_slot(slot),
		Roster.squad_name(squad).to_upper()]
	_squad_label.add_theme_color_override("font_color", Roster.squad_colour(squad))
	_refresh_tickets()


func _refresh_tickets() -> void:
	var one: int = int(GameClient.tickets.get(1, 0))
	var two: int = int(GameClient.tickets.get(2, 0))
	_ticket_label.text = "TICKETS   team 1: %d    team 2: %d" % [one, two]

	var over := GameClient.phase == GameServer.Phase.RESULT
	_result_label.visible = over
	if over:
		var winner := GameClient.winning_team
		var mine := GameClient.my_team
		var verdict := "TEAM %d WINS" % winner
		if mine != Roster.UNALIGNED:
			verdict += "  —  you " + ("won" if mine == winner else "lost")
		_result_label.text = verdict


func _on_possession_changed(entity: Node) -> void:
	_entity = entity
	visible = entity != null


func _on_deploy_map(open: bool) -> void:
	visible = not open and _entity != null


func _on_prompt(text: String) -> void:
	_prompt_label.text = text
	_prompt_label.visible = text != ""


func _process(_delta: float) -> void:
	if GameClient.phase == GameServer.Phase.RESULT:
		visible = true
		_refresh_tickets()
		return
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
	var gauges := "Rotor %.0f%%   Collective %.0f%%" % [
		rotor * 100.0, _entity.collective_fraction() * 100.0]
	if not _entity.can_hover():
		gauges += "   spooling, cannot lift below %.0f%%" % (_entity.hover_rpm_floor() * 100.0)
	elif _entity.exit_refusal() != "":
		gauges += "   %s" % _entity.exit_refusal()
	else:
		gauges += "   F — exit"
	_weapon_label.text = gauges

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
