extends Node3D

class_name DuckHuntHunterPlayer

@export_category("Variables")
@export var look_sensitivity: float = 1
@export var horizontal_limit: float
@export var vertical_limit: float
@export var max_look_sensitivity: float = 20
@export var recoil_curve: Curve
@export var recoil_curve_horizontal: Curve
@export var unzoom_after_shot: bool = true
@export var return_to_zoom_after_shot: bool = false
@export var magazine_capacity: int = 7

@export_category("Nodes")
@export var customization_assigner: CustomizationAssigner
@export var hand_meshes: Array[MeshInstance3D]
@export var laser_mesh: MeshInstance3D

@export var magazine_capacity_by_duck_count: Dictionary[int, int] = {
	# HYPA: vanilla only keyed 0-3, so 4-7 ducks (5-8 players) silently fell back
	# to the base 7 - a near-impossible sniper seat. Extend it so ammo scales.
	0: 7, 
	1: 7, 
	2: 8, 
	3: 10, 
	4: 12, 
	5: 13, 
	6: 14, 
	7: 15, 
}
@export var reload_speed_by_duck_count: Dictionary[int, float] = {
	# HYPA: lower = faster between shots. Extended 4-7 so the hunter fires quicker
	# with more players (more ducks to drop). Was capped at key 3.
	0: 0.95, 
	1: 0.95, 
	2: 0.9, 
	3: 0.8, 
	4: 0.72, 
	5: 0.66, 
	6: 0.6, 
	7: 0.55, 
}

@export_category("Zoom")
@export var zoom_fovs: Array[float] = [
	75.0, 
	50.0, 
	25.0
]
@export var zoom_look_modifiers: Array[float] = [
	1.0, 
	0.6, 
	0.3
]

@export_category("Nodes")
@export var multiplayer_synchronizer: MultiplayerSynchronizer
@export var camera_horizontal: Node3D
@export var camera_vertical: Node3D
@export var camera: Camera3D
@export var hud: CanvasLayer
@export var scope_texture: Control
@export var weapon_parent: Node3D
@export var magnification_indicator: Control

@export var speaker_fire: AudioStreamPlayer

@export var laser_raycast: RayCast3D
@export var laser_parent_node: Node3D
@export var laser_scale_node: Node3D

@export var anim_rig: AnimationPlayer
@export var anim_sensitivity_prompt: AnimationPlayer
@export var rig_parent: Node3D

@export var sens_prompt_full: Control
@export var sens_prompt_slider_only: Control
@export var sens_prompt_label: Label
@export var sensitivity_prompt_parent: Control
@export var keyboard_sensitivity_prompt: Control
@export var controller_sensitivity_prompt: Control
@export var anim_muzzle_flash: AnimationPlayer
@export var smoke_particle_instance: PackedScene
@export var smoke_particle_spawn_pos: Node3D

@export var rect_sensitivity_ui: ColorRect

@export_category("Audio")

@export var speaker_equip_rifle: AudioStreamPlayer
@export var speaker_rack_rifle: AudioStreamPlayer
@export var speaker_reload: AudioStreamPlayer
@export var speaker_scope: AudioStreamPlayer
@export var speaker_headshot: AudioStreamPlayer

@export var sounds_scope: Array[AudioStream]

@export_category("Local Multiplayer")
@export var local_root_node: Node3D
@export var local_viewport: SubViewport
@export var local_camera: Camera3D
@export var role_overlay: Control
@export var role_label: Label

var player_presence: PlayerPresence

var active: bool = false
var zoom_fov_index: float = 0

var look_input: Vector2
var look_recoil: Vector2
var shoot_tween: Tween
var can_aim: bool = false
var can_shoot: bool = true
var recoil_start_rotation: float
var recoil_progress: float = 0.0

var weapon_position: Vector3
var weapon_rotation: Vector3

var num_of_current_rounds_in_magazine = 7

var checking_to_hide_sens_prompt_main: bool = false
var checking_to_hide_sens_prompt: bool = false
var seconds_to_show_sens_prompt: float = 1.0
var sens_prompt_seconds_counted: float = 0.0
var sens_prompt_counting = false

var duck_count: int = 0
var zoom_tween: Tween
var scope_tween: Tween
var scope_text_tween: Tween

func _ready() -> void :
	speaker_scope.volume_linear = 2

	Globals.locale_changed.connect(scale_UI_depending_on_locale)
	scale_UI_depending_on_locale()

func scale_UI_depending_on_locale():
	if GameManager.local_game:
		var changing = false
		match TranslationServer.get_locale():
			"SV":
				changing = true
			"DE":
				changing = true
			"ES":
				changing = true
			"BR":
				changing = true
			"UA":
				changing = true
		if changing:
			controller_sensitivity_prompt.scale = Vector2(0.816, 0.816)
			keyboard_sensitivity_prompt.scale = Vector2(0.816, 0.816)
		else:
			controller_sensitivity_prompt.scale = Vector2(1, 1)
			keyboard_sensitivity_prompt.scale = Vector2(1, 1)

func ready_setup():
	if multiplayer.get_unique_id() != player_presence.network_id: return

	look_sensitivity = Globals.game_settings.get("duck_hunt:look_sensitivity", 1)

func _input(event: InputEvent) -> void :

	if PauseMenu.active:
		return

	if player_presence.using_joystick:
		return

	if can_aim:

		if event is InputEventMouseMotion:

			look_input = Vector2(
				- event.screen_relative.x * look_sensitivity / 1000, 
				- event.screen_relative.y * look_sensitivity / 1000, 
			)

	if event is InputEventMouseButton:

		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			update_sensitivity(0.1)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			update_sensitivity(-0.1)

func update_sensitivity(value: float):

	look_sensitivity = clamp(look_sensitivity + value, 0.1, max_look_sensitivity)
	speaker_scope.stream = sounds_scope[0]
	speaker_scope.volume_linear = 2
	speaker_scope.pitch_scale = 1.5
	if value < 0:
		speaker_scope.pitch_scale = 1.2
	speaker_scope.play()
	if checking_to_hide_sens_prompt_main:
		sens_prompt_counting = true
		if !checking_to_hide_sens_prompt:
			anim_sensitivity_prompt.play("show")
		sens_prompt_seconds_counted = 0
		checking_to_hide_sens_prompt = true


func _process(_delta: float) -> void :

	if GameManager.local_game:

		local_camera.global_transform = camera.global_transform
		local_camera.fov = camera.fov

	count_ui_hide()

	if not GameManager.game_focused:
		return

	if PauseMenu.active:
		return

	if not player_presence:
		return

	process_controller(_delta)
	update_look(_delta)

	if GameManager.local_game:
		if player_presence and player_presence.local_controller_connected:
			if DynamicInput.is_action_just_pressed(player_presence.device_id, "left_shoulder"):
				update_sensitivity(-0.1)
			elif DynamicInput.is_action_just_pressed(player_presence.device_id, "right_shoulder"):
				update_sensitivity(0.1)
	else:
		if DynamicInput.is_action_just_pressed(player_presence.device_id, "left_shoulder"):
			update_sensitivity(-0.1)
		elif DynamicInput.is_action_just_pressed(player_presence.device_id, "right_shoulder"):
			update_sensitivity(0.1)

	if not active:
		return

	if not can_shoot:
		return

	if GameManager.local_game and player_presence and not player_presence.local_controller_connected:
		return

	if (
		DynamicInput.is_action_just_pressed(player_presence.device_id, "action_2") or 
		DynamicInput.is_action_just_pressed(player_presence.device_id, "left_trigger")
	):
		zoom_fov_index = wrap(zoom_fov_index + 1, 0, zoom_fovs.size())
		update_zoom()

	if (
		DynamicInput.is_action_just_pressed(player_presence.device_id, "action_1") or 
		DynamicInput.is_action_just_pressed(player_presence.device_id, "right_trigger")
	):
		shoot()

func process_controller(_delta: float):

	if not can_aim:
		return

	if GameManager.local_game and player_presence and not player_presence.local_controller_connected:
		return

	var controller_input: Vector2 = Vector2(
		(
			DynamicInput.get_action_strength(player_presence.device_id, "right") - 
			DynamicInput.get_action_strength(player_presence.device_id, "left")
		), 
		(
			DynamicInput.get_action_strength(player_presence.device_id, "down") - 
			DynamicInput.get_action_strength(player_presence.device_id, "up")
		)
	).limit_length(1.0)

	if controller_input.length() > Globals.Epsilon:

		look_input = Vector2(
			- controller_input.x * look_sensitivity / 100, 
			- controller_input.y * look_sensitivity / 100, 
		)

func _physics_process(_delta: float) -> void :

	update_laser()
	update_recoil()


	rect_sensitivity_ui.position.x = look_sensitivity * 100 - 225

func count_ui_hide():
	if checking_to_hide_sens_prompt && sens_prompt_counting:
		sens_prompt_seconds_counted += get_process_delta_time()
		if sens_prompt_seconds_counted > seconds_to_show_sens_prompt:
			anim_sensitivity_prompt.play("hide")
			checking_to_hide_sens_prompt = false

func update_look(_delta: float) -> void :

	var horizontal_difference = camera_horizontal.rotation.y
	var vertical_difference = camera_vertical.rotation.x

	camera_horizontal.rotation.y += look_input.x * zoom_look_modifiers[zoom_fov_index]
	camera_vertical.rotation.x += look_input.y * zoom_look_modifiers[zoom_fov_index]


	camera_horizontal.rotation.y = clamp(
		camera_horizontal.rotation.y, - deg_to_rad(horizontal_limit), deg_to_rad(horizontal_limit)
	)
	camera_vertical.rotation.x = clamp(
		camera_vertical.rotation.x, - deg_to_rad(vertical_limit), deg_to_rad(vertical_limit)
	)

	horizontal_difference = (horizontal_difference - camera_horizontal.rotation.y) * 64.0
	vertical_difference = (vertical_difference - camera_vertical.rotation.x) * 64.0
	weapon_parent.rotation_degrees.y = move_toward(
		weapon_parent.rotation_degrees.y, horizontal_difference, _delta * 32.0
	)
	weapon_parent.rotation_degrees.x = move_toward(
		weapon_parent.rotation_degrees.x, vertical_difference, _delta * 32.0
	)

	look_input = look_input.move_toward(Vector2.ZERO, _delta)
	look_recoil = look_recoil.move_toward(Vector2.ZERO, _delta)

func update_recoil():


	camera_vertical.rotation.x += (recoil_curve.sample(recoil_progress) * 0.1) * 0.1
	camera_horizontal.rotation.y += (recoil_curve_horizontal.sample(recoil_progress) * 0.1) * 0.1

func shoot():

	if !can_shoot: return

	laser_scale_node.visible = false

	if laser_raycast.is_colliding():
		var collider = laser_raycast.get_collider()
		if collider is DuckHuntHitbox:

			if collider.player.active:

				if collider.is_head:
					AchievementManager.set_achievement("ACH_11")
					speaker_headshot.play()
					var sc: SpeakerController = speaker_fire.get_child(0)
					sc.speaker.volume_linear = 0
					sc.fade_duration = 0.3
					sc.fade_in()

				var damage = collider.damage_on_hit
				collider.player.shot_rpc.rpc(damage)

			EffectManager.spawn_rpc.rpc(
				&"hit_blood", 
				laser_raycast.get_collision_point(), 
				laser_raycast.get_collision_point() + laser_raycast.get_collision_normal(), 
				Vector3.ONE, 
				true
			)

		else:

			DecalManager.spawn_rpc.rpc(
				&"bullet_hole", 
				laser_raycast.get_collision_point(), 
				laser_raycast.get_collision_point() + laser_raycast.get_collision_normal(), 
				Vector3.ONE * (1.0 + (randf() * 0.25)), 
				true
			)

			EffectManager.spawn_rpc.rpc(
				&"mine_explosion", 
				laser_raycast.get_collision_point(), 
				laser_raycast.get_collision_point() + laser_raycast.get_collision_normal(), 
				Vector3.ONE, 
				true
			)

	recoil_progress = 0.0
	var t = create_tween()
	t.tween_property(
		self, "recoil_progress", 1.0, 0.5
	)

	var zoom_index: float = zoom_fov_index
	can_shoot = false

	recoil_start_rotation = camera_vertical.rotation.x
	look_recoil.x += 0.025 * (-1 + (randf() * 2))

	play_shoot_sound_rpc.rpc()
	if num_of_current_rounds_in_magazine != 1:
		if GameManager.local_game or (multiplayer.get_unique_id() == get_multiplayer_authority()):
			speaker_rack_rifle.play()

	await get_tree().create_timer(0.5).timeout
	if unzoom_after_shot:
		zoom_fov_index = 0
		update_zoom()

	num_of_current_rounds_in_magazine -= 1

	if num_of_current_rounds_in_magazine == 0:
		await reload()
	else:
		anim_rig.play("rifle_pull_bolt_overwrite")


	var cycle_time = reload_speed_by_duck_count.get(duck_count, 0.95)
	await get_tree().create_timer(cycle_time).timeout
	if return_to_zoom_after_shot:
		zoom_fov_index = zoom_index
		update_zoom(zoom_index > 0)
	can_shoot = true

func reload():
	if GameManager.local_game or (multiplayer.get_unique_id() == get_multiplayer_authority()):
		play_reload_sound_rpc.rpc()
	can_shoot = false
	anim_rig.play("rifle_reload_main_overwrite")
	num_of_current_rounds_in_magazine = magazine_capacity
	await get_tree().create_timer(3.8 - 0.95, false).timeout

func update_laser():

	var laser_length: float = 500.0
	if laser_raycast.is_colliding():

		laser_length = (
			laser_raycast.global_position - laser_raycast.get_collision_point()
		).length()

	laser_scale_node.scale.z = laser_length

var sound_toggle_scope = false

func update_zoom(force_show_scope: bool = false):

	if zoom_tween:
		zoom_tween.stop()
	if scope_tween:
		scope_tween.stop()
	if scope_text_tween:
		scope_tween.stop()

	zoom_tween = create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)

	var fov = zoom_fovs[zoom_fov_index]

	laser_scale_node.visible = zoom_fov_index > 0

	zoom_tween.tween_property(camera, "fov", fov, 0.09)

	if zoom_fov_index > 0 or force_show_scope:
		scope_tween = create_tween()
		scope_tween.tween_property(scope_texture, "modulate:a", 1.0, 0.1)
	if zoom_fov_index == 0:
		scope_tween = create_tween()
		scope_tween.tween_property(scope_texture, "modulate:a", 0.0, 0.25)

	sound_toggle_scope = !sound_toggle_scope
	if sound_toggle_scope:
		speaker_scope.stream = sounds_scope[0]
	else:
		speaker_scope.stream = sounds_scope[1]
	speaker_scope.pitch_scale = randf_range(0.95, 1.05)
	speaker_scope.play()

	match zoom_fov_index:
		1.0:
			scope_text_tween = create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_BACK)
			scope_text_tween.tween_property(magnification_indicator, "position", Vector2(523, 374), 0.1)
		2.0:
			scope_text_tween = create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_BACK)
			scope_text_tween.tween_property(magnification_indicator, "position", Vector2(523, 396), 0.1)



@rpc("any_peer", "call_local", "reliable")
func set_can_aim_rpc(_can_aim: bool):
	can_aim = _can_aim

@rpc("any_peer", "call_local", "reliable")
func initialize_hunter_rpc(initial_delay: float):

	if not GameManager.local_game:
		if multiplayer.get_unique_id() != get_multiplayer_authority(): return

	await get_tree().create_timer(initial_delay, false).timeout
	anim_sensitivity_prompt.play("show")
	await get_tree().create_timer(4, false).timeout
	anim_sensitivity_prompt.play("hide")

	checking_to_hide_sens_prompt = false
	checking_to_hide_sens_prompt_main = true

	await get_tree().create_timer(1, false).timeout
	speaker_equip_rifle.play()
	anim_rig.play("rifle_equip_overwrite")

	sens_prompt_full.visible = false
	sens_prompt_label.visible = false
	sensitivity_prompt_parent.visible = false
	sens_prompt_slider_only.visible = true

	anim_sensitivity_prompt.speed_scale *= 1.5

@rpc("any_peer", "call_local", "reliable")
func play_shoot_sound_rpc():
	speaker_fire.play()
	anim_muzzle_flash.play("RESET")
	anim_muzzle_flash.play("flash")
	var smoke_particle: GPUParticles3D = smoke_particle_instance.instantiate()
	add_child(smoke_particle)
	smoke_particle.global_position = smoke_particle_spawn_pos.global_position
	smoke_particle.emitting = true

@rpc("any_peer", "call_local", "reliable")
func play_reload_sound_rpc():
	speaker_reload.play()

@rpc("any_peer", "call_local", "reliable")
func cleanup_rpc():

	if player_presence.network_id == multiplayer.get_unique_id():

		Globals.game_settings["duck_hunt:look_sensitivity"] = look_sensitivity
		Globals.save_game_settings()

	multiplayer_synchronizer.public_visibility = false

@rpc("any_peer", "call_local", "reliable")
func set_active_rpc(_active: bool) -> void :
	active = _active

	magazine_capacity = magazine_capacity_by_duck_count.get(
		duck_count, 7
	)
	num_of_current_rounds_in_magazine = magazine_capacity

@rpc("any_peer", "call_local", "reliable")
func set_player_presence(network_id: int) -> void :
	player_presence = PlayerManager.player_presences[network_id]
	set_multiplayer_authority(player_presence.network_id, true)

	if GameManager.local_game:

		local_camera.current = true
		if not player_presence.using_joystick:
			local_viewport.physics_object_picking = true

		hud.reparent(local_viewport)

		laser_mesh.set_layer_mask_value(1, false)
		laser_mesh.set_layer_mask_value(11, true)
		hud.visible = true

		if player_presence.using_joystick:
			_on_input_device_changed(GameManager.InputDevice.Controller)
		else:
			_on_input_device_changed(GameManager.InputDevice.Keyboard)





		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

		var customization_data = player_presence.customization
		var hands_texture: Texture = customization_assigner.get_suit_texture(
			customization_data[2]
		)

		if not hand_meshes.is_empty():

			var material: StandardMaterial3D = hand_meshes[0].get_active_material(0).duplicate()
			material.albedo_texture = hands_texture

			for hm in hand_meshes:
				hm.set_surface_override_material(0, material)

		return

	if player_presence.network_id == multiplayer.get_unique_id():

		CursorManager.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		laser_parent_node.visible = false
		hud.visible = true

		camera.current = true
		var ui_nodes = get_tree().get_nodes_in_group(Globals.GROUP_UI)
		for ui_node in ui_nodes:
			ui_node.visible = false

		ready_setup()

	if network_id == multiplayer.get_unique_id():

		var customization_data = player_presence.customization
		var hands_texture: Texture = customization_assigner.get_suit_texture(
			customization_data[2]
		)

		if not hand_meshes.is_empty():

			var material: StandardMaterial3D = hand_meshes[0].get_active_material(0).duplicate()
			material.albedo_texture = hands_texture

			for hm in hand_meshes:
				hm.set_surface_override_material(0, material)

		GameManager.input_device_changed.connect(_on_input_device_changed)
		_on_input_device_changed(GameManager.current_input_device)

	else:

		speaker_reload.volume_db -= 20.0

		set_process_input(false)
		set_process(false)
		set_physics_process(false)

@rpc("any_peer", "call_local", "reliable")
func setup_rpc(_position: Vector3, _duck_count: int):
	global_position = _position
	duck_count = _duck_count



func _on_input_device_changed(input_device: GameManager.InputDevice):

	match input_device:

		GameManager.InputDevice.Keyboard:
			keyboard_sensitivity_prompt.visible = true
			controller_sensitivity_prompt.visible = false
		GameManager.InputDevice.Controller:
			keyboard_sensitivity_prompt.visible = false
			controller_sensitivity_prompt.visible = true



func reveal_role():

	role_label.text = tr("LOC_CONTROL_HUNTER_NAME") % player_presence.network_name

	role_overlay.modulate.a = 1.0
	role_overlay.visible = true

	role_label.modulate.a = 0.0
	role_label.visible = true

	var t: = create_tween()
	t.tween_property(role_label, "modulate:a", 1.0, 1.0)
	await t.finished
	await get_tree().create_timer(1.0).timeout

	t = create_tween()
	t.tween_property(role_label, "modulate:a", 0.0, 0.5)
	t.tween_property(role_overlay, "modulate:a", 0.0, 0.5).set_delay(0.5)
	await t.finished

	set_can_aim_rpc(true)
