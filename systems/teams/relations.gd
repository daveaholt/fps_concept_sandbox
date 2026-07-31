class_name Relations
extends RefCounted

const SQUAD := Color(0.35, 0.95, 0.5)
const TEAM := Color(0.42, 0.68, 1.0)
const ENEMY := Color(1.0, 0.42, 0.36)


static func colour_for(roster: Roster, viewer_peer: int, viewer_team: int,
		peer: int) -> Color:
	if roster.team_of(peer) != viewer_team:
		return ENEMY
	if roster.squad_of(peer) == roster.squad_of(viewer_peer):
		return SQUAD
	return TEAM


static func is_enemy(colour: Color) -> bool:
	return colour == ENEMY
