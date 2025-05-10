extends Node3D
class_name Gun

# Gun properties
@export var damage := 20.0
@export var fire_rate := 0.1  # Time between shots in seconds
@export var ammo_capacity := 30
@export var reload_time := 1.5
@export var automatic := true  # If false, requires click for each shot
@export var recoil_amount := 0.1
@export var spread := 0.02  # Bullet spread/accuracy
@export var max_distance := 1000.0  # Maximum raycast distance

# Internal variables
var current_ammo: int
var can_fire := true
var is_reloading := false
var fire_timer := 0.0
var reload_timer := 0.0

# References
@onready var raycast: RayCast3D
@onready var muzzle_flash: GPUParticles3D
@onready var audio_player: AudioStreamPlayer3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	current_ammo = ammo_capacity
	
	# Create raycast if it doesn't exist
	if !has_node("RayCast3D"):
		raycast = RayCast3D.new()
		raycast.name = "RayCast3D"
		add_child(raycast)
	else:
		raycast = $RayCast3D
	
	raycast.enabled = true
	raycast.target_position = Vector3(0, 0, -max_distance)
	raycast.collision_mask = 1  # Adjust to your collision layers
	
	# Create muzzle flash if it doesn't exist
	if !has_node("MuzzleFlash"):
		muzzle_flash = GPUParticles3D.new()
		muzzle_flash.name = "MuzzleFlash"
		add_child(muzzle_flash)
		
		# Set up basic particle properties
		var material = ParticleProcessMaterial.new()
		material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
		material.direction = Vector3(0, 0, -1)
		material.spread = 30.0
		material.initial_velocity_min = 1.0
		material.initial_velocity_max = 3.0
		material.scale_min = 0.1
		material.scale_max = 0.3
		material.color = Color(1.0, 0.7, 0.0, 1.0)
		muzzle_flash.process_material = material
		
		# Create a simple mesh for particles
		var mesh = QuadMesh.new()
		mesh.size = Vector2(0.1, 0.1)
		muzzle_flash.draw_pass_1 = mesh
	else:
		muzzle_flash = $MuzzleFlash
	
	muzzle_flash.emitting = false
	muzzle_flash.one_shot = true
	muzzle_flash.explosiveness = 0.9
	muzzle_flash.transform.origin = Vector3(0, 0, -0.5)  # Position at end of gun
	
	# Create audio player if it doesn't exist
	if !has_node("AudioStreamPlayer3D"):
		audio_player = AudioStreamPlayer3D.new()
		audio_player.name = "AudioStreamPlayer3D"
		add_child(audio_player)
	else:
		audio_player = $AudioStreamPlayer3D

func _process(delta: float) -> void:
	# Handle timers
	if !can_fire:
		fire_timer += delta
		if fire_timer >= fire_rate:
			can_fire = true
			fire_timer = 0.0
	
	if is_reloading:
		reload_timer += delta
		if reload_timer >= reload_time:
			finish_reload()
	
	# Handle firing
	if Input.is_action_pressed("fire") and automatic and can_fire and !is_reloading and current_ammo > 0:
		fire()
	elif Input.is_action_just_pressed("fire") and !automatic and can_fire and !is_reloading and current_ammo > 0:
		fire()
	elif Input.is_action_just_pressed("fire") and current_ammo <= 0:
		play_empty_sound()
	
	# Handle reload
	if Input.is_action_just_pressed("reload") and !is_reloading and current_ammo < ammo_capacity:
		start_reload()

func fire() -> void:
	current_ammo -= 1
	can_fire = false
	fire_timer = 0.0
	
	# Play sound
	play_fire_sound()
	
	# Show muzzle flash
	muzzle_flash.restart()
	muzzle_flash.emitting = true
	
	# Apply recoil to camera
	apply_recoil()
	
	# Perform raycast for hit detection
	perform_raycast()

func perform_raycast() -> void:
	# Apply random spread
	if spread > 0:
		raycast.target_position = Vector3(
			randf_range(-spread, spread),
			randf_range(-spread, spread),
			-max_distance
		)
	
	# Force raycast update
	raycast.force_raycast_update()
	
	if raycast.is_colliding():
		var collision_point = raycast.get_collision_point()
		var collision_normal = raycast.get_collision_normal()
		var collider = raycast.get_collider()
		
		# Create impact effect
		create_impact_effect(collision_point, collision_normal)
		
		# Apply damage if the collider has a take_damage method
		apply_damage(collider)

func apply_damage(collider: Object) -> void:
	# Check if the collider has a take_damage method
	if collider.has_method("take_damage"):
		collider.take_damage(damage)
	
	# Check if it's an enemy with health component
	if collider.get_parent() and collider.get_parent().has_method("take_damage"):
		collider.get_parent().take_damage(damage)

func apply_recoil() -> void:
	# Get the camera node
	var camera = get_viewport().get_camera_3d()
	if camera and camera.get_parent() and camera.get_parent().has_method("apply_recoil"):
		camera.get_parent().apply_recoil(recoil_amount)

func create_impact_effect(position: Vector3, normal: Vector3) -> void:
	# Create a simple impact effect
	var impact = Node3D.new()
	get_tree().current_scene.add_child(impact)
	impact.global_position = position
	
	# Create particles for impact
	var particles = GPUParticles3D.new()
	impact.add_child(particles)
	
	# Set up particle properties
	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	material.direction = normal
	material.spread = 60.0
	material.initial_velocity_min = 1.0
	material.initial_velocity_max = 3.0
	material.scale_min = 0.05
	material.scale_max = 0.1
	material.color = Color(0.7, 0.7, 0.7, 1.0)
	particles.process_material = material
	
	# Create a simple mesh for particles
	var mesh = QuadMesh.new()
	mesh.size = Vector2(0.05, 0.05)
	particles.draw_pass_1 = mesh
	
	# Configure particles
	particles.emitting = true
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.amount = 10
	
	# Add a light for impact flash
	var light = OmniLight3D.new()
	impact.add_child(light)
	light.light_color = Color(1.0, 0.8, 0.5)
	light.light_energy = 1.0
	light.omni_range = 2.0
	
	# Fade out light
	var tween = impact.create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.1)
	
	# Auto-remove after particles finish
	await get_tree().create_timer(1.0).timeout
	impact.queue_free()

func start_reload() -> void:
	is_reloading = true
	reload_timer = 0.0
	
	# Play reload sound
	play_reload_sound()

func finish_reload() -> void:
	current_ammo = ammo_capacity
	is_reloading = false
	reload_timer = 0.0

func play_fire_sound() -> void:
	# Simple beep sound if no custom sound is set
	audio_player.pitch_scale = randf_range(0.9, 1.1)  # Slight random pitch
	audio_player.play()

func play_empty_sound() -> void:
	audio_player.pitch_scale = 0.5
	audio_player.play()

func play_reload_sound() -> void:
	audio_player.pitch_scale = 0.7
	audio_player.play()
