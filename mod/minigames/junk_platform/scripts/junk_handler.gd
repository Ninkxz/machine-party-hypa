extends Node

class_name JunkPlatformJunkHandler

const junk_scene = preload("uid://c0tipjbyg5ofd")

@export_category("Variables")
@export var spawn_interval: float = 4.0            # HYPA: metal starts slower (was 3.0)
@export var min_spawn_interval: float = 1.8        # HYPA: never as brutal (was 1.0)
@export var time_to_spawn_interval_limit: float = 14.0  # HYPA: ramps up slower (was 10.0)
@export var max_junk: int = 40
@export var platform_radius: float = 6.0

@export_category("Nodes")
@export var junks_node: Node3D
@export var timer: Timer
@export var junk_catcher: Area3D

var spawn_points: Dictionary[int, Vector3]
var active: bool = false
var counter: int = 0

var junk_instances: Dictionary[int, JunkCubeRigidbody]

var caught_junk: Array[JunkCubeRigidbody]
var elapsed: float = 0.0

func _ready() -> void :

	if multiplayer.is_server():
		junk_catcher.body_entered.connect(_on_catcher_body_entered)
		timer.timeout.connect(_on_timer_timeout)

func _physics_process(_delta: float) -> void :

	if not multiplayer.is_server():
		return

	if active:
		elapsed += _delta

	var data: Dictionary[int, Transform3D]
	for k in junk_instances.keys():
		if junk_instances[k].active:
			data[k] = junk_instances[k].global_transform

	updata_junk_positions_rpc.rpc(data)

func set_active(_active: bool):
	active = _active
	if active:
		timer.start(spawn_interval)

func add_spawn_point(_network_id: int, _position: Vector3):
	spawn_points[_network_id] = _position

func remove_spawn_point(_network_id: int):
	spawn_points.erase(_network_id)



@rpc("any_peer", "call_local", "reliable")
func register_junk_cube_rpc(index: int, junk_cube_path: NodePath):
	junk_instances[index] = get_node(junk_cube_path)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func updata_junk_positions_rpc(data: Dictionary[int, Transform3D]):

	for key in data.keys():
		junk_instances[key].global_transform = data[key]



func _on_timer_timeout():
	for p in spawn_points.values():
		var junk_instance: JunkCubeRigidbody
		if not caught_junk.is_empty():
			junk_instance = caught_junk.pop_front()
		elif counter < max_junk:
			junk_instance = junk_scene.instantiate()
			junks_node.add_child(junk_instance, true)
			register_junk_cube_rpc.rpc(
				junk_instances.size(), 
				junk_instance.get_path()
			)
			counter += 1

		if junk_instance:


			var random_rot: float = TAU * randf()
			var random_vector: Vector3 = Vector3(
				cos(random_rot), 0.0, sin(random_rot)
			) * (randf() * platform_radius)
			var random_torque: Vector3 = Vector3(
				-1.0 + (randf() * 2.0), 
				-1.0 + (randf() * 2.0), 
				-1.0 + (randf() * 2.0)
			)

			junk_instance.setup_rpc.rpc(p + random_vector, random_torque, true)

	var spawn_time = lerp(
		spawn_interval, min_spawn_interval, min(elapsed, time_to_spawn_interval_limit) / time_to_spawn_interval_limit
	)

	timer.start(spawn_time)

func _on_catcher_body_entered(body):

	if body is JunkCubeRigidbody:
		body.reset_rpc.rpc()
		caught_junk.append(body)
