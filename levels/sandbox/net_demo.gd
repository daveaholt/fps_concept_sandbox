extends Node3D

const BALL_SCENE := preload("res://entities/net_demo/bouncing_ball.tscn")

@export var spawn_position: Vector3 = Vector3(0.0, 14.0, 40.0)


func _ready() -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		return

	var ball := BALL_SCENE.instantiate()
	ball.name = "ProbeBall"
	ball.position = spawn_position
	$Spawned.add_child(ball, true)
	print("[net_demo] server spawned ProbeBall at %v" % spawn_position)
