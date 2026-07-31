extends Control

const RETICLE_RANGE := 150.0
const BANNER_SECONDS := 2.4

var _entity: Node = null

@onready var _crosshair: Control = $Crosshair
@onready var _weapon_label: Label = $Bottom/WeaponLabel
@onready var _health_label: Label = $Bottom/HealthLabel
@onready var _draw_bar: ProgressBar = $Bottom/DrawBar
@onready var _prompt_label: Label = $PromptLabel

var _squad_label: Label
var _ticket_label: Label
var _result_label: Label
var _controls_label: Label
var _hull_indicator: HullIndicator
var _hit_marker: HitMarker
var _kill_banner: Label
var _banner_left: float = 0.0


func _ready() -> void:
	var panel: VBoxContainer = $Bottom
	_controls_label = Label.new()
	_controls_label.name = "ControlsLabel"
	_controls_label.add_theme_color_override("font_color", Color(0.72, 0.76, 0.82))
	_controls_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_controls_label.add_theme_constant_override("outline_size", 5)
	panel.add_child(_controls_label)

	_squad_label = Label.new()
	_squad_label.name = "SquadLabel"
	panel.add_child(_squad_label)
	panel.move_child(_squad_label, 0)

	_ticket_label = Label.new()
	_ticket_label.name = "TicketLabel"
	panel.add_child(_ticket_label)
	panel.move_child(_ticket_label, 1)

	_result_label = Label.new()
	_result_label.name = "ResultLabel"
	_result_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_result_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_result_label.position = Vector2(0.0, 120.0)
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.visible = false
	add_child(_result_label)

	_hull_indicator = HullIndicator.new()
	_hull_indicator.name = "HullIndicator"
	_hull_indicator.visible = false
	add_child(_hull_indicator)

	_hit_marker = HitMarker.new()
	_hit_marker.name = "HitMarker"
	add_child(_hit_marker)

	_kill_banner = Label.new()
	_kill_banner.name = "KillBanner"
	_kill_banner.set_anchors_preset(Control.PRESET_CENTER)
	_kill_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_kill_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_kill_banner.position = Vector2(0.0, 74.0)
	_kill_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_kill_banner.add_theme_font_size_override("font_size", 26)
	_kill_banner.add_theme_color_override("font_color", Color(1.0, 0.42, 0.32))
	_kill_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_kill_banner.add_theme_constant_override("outline_size", 6)
	_kill_banner.visible = false
	_kill_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_kill_banner)

	EventBus.hit_confirmed.connect(_on_hit_confirmed)
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
	_tick_banner(_delta)
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
	_hit_marker.global_position = _crosshair.global_position
	_hull_indicator.visible = false
	if _entity.is_in_group("helicopter"):
		_helicopter_panel()
	elif _entity.is_in_group("vehicle"):
		_vehicle_panel()
	else:
		_infantry_panel()
	_refresh_controls()


func _refresh_controls() -> void:
	if not _entity.is_in_group("vehicle"):
		_controls_label.text = ""
		return
	var hints := ["%s fire" % InputHints.label(_fire_action())]
	var sampler := GameClient.sampler
	if sampler != null and sampler.can_zoom():
		hints.append("%s zoom" % InputHints.label("zoom"))
	if _entity.seats.count() > 1:
		hints.append("%s switch seat" % InputHints.label("switch_seat"))
	hints.append("%s exit" % InputHints.label("exit_vehicle"))
	_controls_label.text = "   ·   ".join(hints)


func _on_hit_confirmed(_damage: float, killed: bool, label: String) -> void:
	_hit_marker.flash(killed)
	if label == "":
		return
	_kill_banner.text = label
	_kill_banner.visible = true
	_banner_left = BANNER_SECONDS


func _tick_banner(delta: float) -> void:
	if _banner_left <= 0.0:
		return
	_banner_left = maxf(0.0, _banner_left - delta)
	_kill_banner.modulate.a = clampf(_banner_left / 0.6, 0.0, 1.0)
	if _banner_left <= 0.0:
		_kill_banner.visible = false


func _refresh_hull_indicator() -> void:
	if not _entity.has_method("using_first_person") or not _entity.using_first_person():
		return
	_hull_indicator.visible = true
	_hull_indicator.global_position = _crosshair.global_position
	_hull_indicator.set_hull_angle(_entity.turret_angles().x)


func _condition() -> String:
	if not _entity.has_method("health_fraction"):
		return ""
	var state: String = VehicleDamage.label(_entity.damage_state())
	return "HULL %d%%%s" % [roundi(_entity.health_fraction() * 100.0),
		"  " + state if state != "" else ""]


func _seat() -> int:
	return _entity.seat_of(GameClient.get_peer_id())


func _fire_action() -> String:
	var sampler := GameClient.sampler
	return sampler.fire_action() if sampler != null else "fire"


func _aim_reticle() -> void:
	var camera := get_viewport().get_camera_3d()
	var centre := get_viewport_rect().size * 0.5
	if camera == null or not _entity.has_method("weapon_ray"):
		_crosshair.global_position = centre
		return
	var ray: Array = _entity.weapon_ray(_seat())
	if ray.size() < 3:
		_crosshair.global_position = centre
		return
	var point := _impact_point(ray[0] as Vector3, ray[1] as Vector3, ray[2] as int)
	if camera.is_position_behind(point):
		_crosshair.modulate.a = 0.0
		return
	_crosshair.global_position = camera.unproject_position(point)


func _impact_point(origin: Vector3, direction: Vector3, params_id: int) -> Vector3:
	var flat := origin + direction * RETICLE_RANGE
	var manager := GameClient.ballistics
	if manager == null:
		return flat
	var params: ProjectileParams = manager.params_for(params_id)
	if params == null or params.muzzle_velocity <= 0.0:
		return flat
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var flight := RETICLE_RANGE / params.muzzle_velocity
	return flat + Vector3.DOWN * 0.5 * gravity * params.gravity_scale * flight * flight


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
	_crosshair.global_position = get_viewport_rect().size * 0.5


func _helicopter_panel() -> void:
	_health_label.text = "%s   %.0f km/h   %.0f m AGL   %+.1f m/s   %s" % [
		_entity.get_display_name(), _entity.speed_kmh(),
		_entity.altitude_agl(), _entity.climb_rate(), _condition()]

	if _seat() > Seats.DRIVER:
		_health_label.text = "%s   GUNNER   %.0f m AGL" % [
			_entity.get_display_name(), _entity.altitude_agl()]
		_weapon_label.text = "Minigun — %s   heat %.0f%%%s" % [
			InputHints.label(_fire_action()), _entity.gun_heat() * 100.0,
			"   OVERHEATED" if _entity.gun_heat() >= 1.0 else ""]
		_draw_bar.visible = true
		_draw_bar.value = _entity.gun_heat() * 100.0
		_crosshair.modulate.a = 1.0
		_aim_reticle()
		return

	var rotor: float = _entity.rotor_fraction()
	var gauges := "Rotor %.0f%%   Collective %.0f%%" % [
		rotor * 100.0, _entity.collective_fraction() * 100.0]
	if not _entity.can_hover():
		gauges += "   spooling, cannot lift below %.0f%%" % (_entity.hover_rpm_floor() * 100.0)
	elif _entity.exit_refusal() != "":
		gauges += "   %s" % _entity.exit_refusal()
	else:
		gauges += "   Rockets %d/%d" % [_entity.rockets_left(), _entity.rocket_salvo]
	_weapon_label.text = gauges

	_draw_bar.visible = true
	_draw_bar.value = _entity.collective_fraction() * 100.0
	_crosshair.modulate.a = 1.0 if _entity.can_hover() else 0.4
	_aim_reticle()


func _vehicle_panel() -> void:
	_health_label.text = "%s   %.0f km/h   %s" % [_entity.get_display_name(),
		_entity.speed_kmh(), _condition()]

	if _seat() > Seats.DRIVER:
		_weapon_label.text = "MG — %s   heat %.0f%%%s" % [
			InputHints.label(_fire_action()), _entity.gun_heat() * 100.0,
			"   OVERHEATED" if _entity.gun_heat() >= 1.0 else ""]
		_draw_bar.visible = true
		_draw_bar.value = _entity.gun_heat() * 100.0
		_crosshair.modulate.a = 1.0
		_aim_reticle()
		return

	_refresh_hull_indicator()

	var reload: float = _entity.reload_fraction()
	_weapon_label.text = ("Cannon ready — %s" % InputHints.label(_fire_action())
		if reload >= 1.0 else "Reloading")
	_draw_bar.visible = reload < 1.0
	_draw_bar.value = reload * 100.0
	_crosshair.modulate.a = 1.0 if reload >= 1.0 else 0.5
	_aim_reticle()
