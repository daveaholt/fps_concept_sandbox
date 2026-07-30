extends Node

signal possession_changed(new_controllable: Node)
signal deploy_map_toggled(is_open: bool)
signal interaction_prompt(text: String)
signal hit_confirmed(damage: float, killed: bool)
signal roster_changed()
