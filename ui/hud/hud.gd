extends Control

const RETICLE_RANGE := 150.0
const BANNER_SECONDS := 2.4
const MARGIN := 24.0
const TEAM_BLUE := Color(0.42, 0.68, 1.0)
const ENEMY_RED := Color(1.0, 0.42, 0.36)
const SQUAD_GREEN := Color(0.35, 0.95, 0.5)
const DIM := Color(0.5, 0.53, 0.58)
const TICKET_BAR := Vector2(96.0, 7.0)
const MATE_BAR := Vector2(74.0, 6.0)
const HEALTH_BAR := Vector2(190.0, 10.0)

var _entity: Node = null
var _banner_left: float = 0.0

@onready var _crosshair: Control = $Crosshair
@onready var _prompt_label: Label = $PromptLabel

var _hit_marker: HitMarker
var _hull_indicator: HullIndicator
var _reload_label: Label
var _kill_banner: Label
var _result_label: Label

var _minimap: Minimap
var _mine_count: Label
var _mine_bar: StatusBar
var _their_count: Label
var _their_bar: StatusBar

var _squad_rows: Array = []
var _weapon_label: Label
var _ammo_label: Label
var _health_bar: StatusBar


func _ready() -> void:
	var legacy: Node = get_node_or_null("Bottom")
	if legacy != null:
		legacy.queue_free()

	_build_centre()
	_build_situation()
	_build_self()

	EventBus.roster_changed.connect(_refresh_tickets)
	EventBus.possession_changed.connect(_on_possession_changed)
	EventBus.interaction_prompt.connect(_on_prompt)
	EventBus.deploy_map_toggled.connect(_on_deploy_map)
	EventBus.hit_confirmed.connect(_on_hit_confirmed)
	_on_possession_changed(GameClient.my_entity)
	_refresh_tickets()


func _label(text: String, font_size: int, tint: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var made := Label.new()
	made.text = text
	made.horizontal_alignment = align
	made.mouse_filter = Control.MOUSE_FILTER_IGNORE
	made.add_theme_font_size_override("font_size", font_size)
	made.add_theme_color_override("font_color", tint)
	made.add_theme_color_override("font_outline_color", Color.BLACK)
	made.add_theme_constant_override("outline_size", 5)
	return made


func _build_centre() -> void:
	_hit_marker = HitMarker.new()
	_hit_marker.name = "HitMarker"
	add_child(_hit_marker)

	_hull_indicator = HullIndicator.new()
	_hull_indicator.name = "HullIndicator"
	_hull_indicator.visible = false
	add_child(_hull_indicator)

	_reload_label = _label("", 22, Color(1.0, 0.85, 0.45), HORIZONTAL_ALIGNMENT_CENTER)
	_reload_label.name = "ReloadLabel"
	_reload_label.set_anchors_preset(Control.PRESET_CENTER)
	_reload_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_reload_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_reload_label.position = Vector2(0.0, 40.0)
	_reload_label.visible = false
	add_child(_reload_label)

	_kill_banner = _label("", 26, ENEMY_RED, HORIZONTAL_ALIGNMENT_CENTER)
	_kill_banner.name = "KillBanner"
	_kill_banner.set_anchors_preset(Control.PRESET_CENTER)
	_kill_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_kill_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_kill_banner.position = Vector2(0.0, 74.0)
	_kill_banner.visible = false
	add_child(_kill_banner)

	_result_label = _label("", 34, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_result_label.name = "ResultLabel"
	_result_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_result_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_result_label.position = Vector2(0.0, 120.0)
	_result_label.visible = false
	add_child(_result_label)


func _build_situation() -> void:
	var column := VBoxContainer.new()
	column.name = "Situation"
	column.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	column.position = Vector2(MARGIN, -MARGIN)
	column.add_theme_constant_override("separation", 8)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	var tickets := HBoxContainer.new()
	tickets.add_theme_constant_override("separation", 18)
	tickets.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(tickets)

	_mine_count = _label("0", 24, TEAM_BLUE)
	_mine_bar = StatusBar.new()
	tickets.add_child(_ticket_block(_mine_count, _mine_bar, TEAM_BLUE))

	_their_count = _label("0", 24, ENEMY_RED)
	_their_bar = StatusBar.new()
	tickets.add_child(_ticket_block(_their_count, _their_bar, ENEMY_RED))

	_minimap = Minimap.new()
	_minimap.name = "Minimap"
	column.add_child(_minimap)


func _ticket_block(count: Label, bar: StatusBar, tint: Color) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(count)
	bar.setup(TICKET_BAR.x, TICKET_BAR.y, tint)
	box.add_child(bar)
	return box


func _build_self() -> void:
	var column := VBoxContainer.new()
	column.name = "Self"
	column.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	column.position = Vector2(-MARGIN, -MARGIN)
	column.alignment = BoxContainer.ALIGNMENT_END
	column.add_theme_constant_override("separation", 6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	var squad := VBoxContainer.new()
	squad.name = "SquadList"
	squad.alignment = BoxContainer.ALIGNMENT_END
	squad.add_theme_constant_override("separation", 3)
	squad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(squad)

	for _i in Roster.SQUAD_SIZE - 1:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_END
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var name_label := _label("", 17, SQUAD_GREEN, HORIZONTAL_ALIGNMENT_RIGHT)
		var bar := StatusBar.new()
		bar.setup(MATE_BAR.x, MATE_BAR.y, SQUAD_GREEN)
		row.add_child(name_label)
		row.add_child(bar)
		row.visible = false
		squad.add_child(row)
		_squad_rows.append({"row": row, "name": name_label, "bar": bar})

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 10.0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)

	_weapon_label = _label("", 22, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	column.add_child(_weapon_label)

	_ammo_label = _label("", 26, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	column.add_child(_ammo_label)

	_health_bar = StatusBar.new()
	_health_bar.setup(HEALTH_BAR.x, HEALTH_BAR.y, SQUAD_GREEN)
	column.add_child(_health_bar)


func _refresh_tickets() -> void:
	var mine := GameClient.my_team
	var theirs := 2 if mine == 1 else 1
	var mine_left := int(GameClient.tickets.get(mine, 0))
	var their_left := int(GameClient.tickets.get(theirs, 0))
	_mine_count.text = str(mine_left)
	_their_count.text = str(their_left)
	_mine_bar.set_fraction(float(mine_left) / float(GameServer.START_TICKETS))
	_their_bar.set_fraction(float(their_left) / float(GameServer.START_TICKETS))

	var over := GameClient.phase == GameServer.Phase.RESULT
	_result_label.visible = over
	if over:
		var winner := GameClient.winning_team
		var verdict := "TEAM %d WINS" % winner
		if mine != Roster.UNALIGNED:
			verdict += "  —  you " + ("won" if mine == winner else "lost")
		_result_label.text = verdict


func _refresh_squad() -> void:
	var mates: Array = GameClient.roster.squadmates(GameClient.get_peer_id())
	for i in _squad_rows.size():
		var entry: Dictionary = _squad_rows[i]
		if i >= mates.size():
			entry["row"].visible = false
			continue
		var peer: int = mates[i]
		entry["row"].visible = true
		entry["name"].text = GameClient.roster.name_of(peer)

		var body := GameClient.squadmate_entity(peer)
		if body == null or not is_instance_valid(body):
			entry["name"].add_theme_color_override("font_color", DIM)
			entry["bar"].set_colour(DIM)
			entry["bar"].set_fraction(0.0)
			continue
		entry["name"].add_theme_color_override("font_color", SQUAD_GREEN)
		entry["bar"].set_colour(SQUAD_GREEN)
		entry["bar"].set_fraction(health_fraction_of(body))


func _refresh_minimap() -> void:
	if _entity == null or not is_instance_valid(_entity) or not _entity is Node3D:
		_minimap.go_dark()
		return

	var mates: Array = []
	for peer in GameClient.roster.squadmates(GameClient.get_peer_id()):
		var body := GameClient.squadmate_entity(peer)
		if body != null and is_instance_valid(body):
			mates.append(body.global_position)

	var spawns: Array = []
	for node in get_tree().get_nodes_in_group("spawn_points"):
		if node is Node3D and node.enabled:
			spawns.append((node as Node3D).global_position)

	var pings: Array = []
	for shot in GameClient.gunshots:
		var age: float = shot["age"]
		pings.append({"position": shot["position"],
			"fade": 1.0 - clampf(age / GameClient.GUNSHOT_FADE_SECONDS, 0.0, 1.0)})

	_minimap.show_world((_entity as Node3D).global_position, _view_yaw(), mates,
		spawns, pings)


func _view_yaw() -> float:
	if GameClient.sampler != null and not _entity.is_in_group("vehicle"):
		return GameClient.sampler.yaw
	return (_entity as Node3D).global_transform.basis.get_euler().y


func health_fraction_of(body: Node) -> float:
	if body.has_method("health_fraction"):
		return body.health_fraction()
	if body.get("state") != null:
		return clampf(body.state.health / 100.0, 0.0, 1.0)
	return 1.0


func _on_possession_changed(entity: Node) -> void:
	_entity = entity
	visible = entity != null


func _on_deploy_map(open: bool) -> void:
	visible = not open and _entity != null


func _on_prompt(text: String) -> void:
	_prompt_label.text = text
	_prompt_label.visible = text != ""


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


func _process(delta: float) -> void:
	_tick_banner(delta)
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
	_reload_label.visible = false
	_hull_indicator.visible = false
	_hit_marker.global_position = _crosshair.global_position
	_refresh_tickets()
	_refresh_squad()
	_refresh_minimap()

	if _entity.is_in_group("helicopter"):
		_helicopter_panel()
	elif _entity.is_in_group("vehicle"):
		_vehicle_panel()
	else:
		_infantry_panel()


func _seat() -> int:
	return _entity.seat_of(GameClient.get_peer_id())


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
	_health_bar.set_colour(SQUAD_GREEN)
	_health_bar.set_fraction(state.health / 100.0)
	_crosshair.global_position = get_viewport_rect().size * 0.5

	var weapon: WeaponDef = _entity.get_active_weapon()
	if weapon == null:
		_weapon_label.text = "—"
		_ammo_label.text = ""
		return

	var drawing := state.switch_progress < 1.0
	_crosshair.modulate.a = 0.35 if drawing else 1.0
	_weapon_label.text = weapon.display_name
	_ammo_label.text = "%d / %d" % [state.loaded(state.weapon_index),
		state.spare(state.weapon_index)]

	if state.reloading():
		_reload_label.text = "RELOADING"
		_reload_label.visible = true
	elif state.loaded(state.weapon_index) <= 0 and state.spare(state.weapon_index) > 0:
		_reload_label.text = "RELOAD  [%s]" % InputHints.label("reload")
		_reload_label.visible = true


func _helicopter_panel() -> void:
	_vehicle_health()
	if _seat() > Seats.DRIVER:
		_weapon_label.text = "Minigun"
		_ammo_label.text = "heat %.0f%%%s" % [_entity.gun_heat() * 100.0,
			"  OVERHEATED" if _entity.gun_heat() >= 1.0 else ""]
		_crosshair.modulate.a = 1.0
		_aim_reticle()
		return

	_weapon_label.text = "Rockets   rotor %.0f%%" % (_entity.rotor_fraction() * 100.0)
	if not _entity.can_hover():
		_ammo_label.text = "spooling"
	elif _entity.exit_refusal() != "":
		_ammo_label.text = _entity.exit_refusal()
	else:
		_ammo_label.text = "%d / %d" % [_entity.rockets_left(), _entity.rocket_salvo]
	_crosshair.modulate.a = 1.0 if _entity.can_hover() else 0.4
	_aim_reticle()


func _vehicle_panel() -> void:
	_vehicle_health()
	if _seat() > Seats.DRIVER:
		_weapon_label.text = "Machine gun"
		_ammo_label.text = "heat %.0f%%%s" % [_entity.gun_heat() * 100.0,
			"  OVERHEATED" if _entity.gun_heat() >= 1.0 else ""]
		_crosshair.modulate.a = 1.0
		_aim_reticle()
		return

	if _entity.has_method("using_first_person") and _entity.using_first_person():
		_hull_indicator.visible = true
		_hull_indicator.global_position = _crosshair.global_position
		_hull_indicator.set_hull_angle(_entity.turret_angles().x)

	var reload: float = _entity.reload_fraction()
	_weapon_label.text = "Cannon"
	_ammo_label.text = "ready" if reload >= 1.0 else "reloading"
	_crosshair.modulate.a = 1.0 if reload >= 1.0 else 0.5
	_aim_reticle()


func _vehicle_health() -> void:
	var fraction: float = _entity.health_fraction()
	var state: String = VehicleDamage.label(_entity.damage_state())
	_health_bar.set_fraction(fraction)
	_health_bar.set_colour(ENEMY_RED if state == "CRITICAL" else SQUAD_GREEN)
	if state != "":
		_reload_label.text = "%s  %s" % [_entity.get_display_name().to_upper(), state]
		_reload_label.visible = true
