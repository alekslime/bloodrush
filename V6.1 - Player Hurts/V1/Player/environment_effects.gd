extends Node3D
class_name EnvironmentEffects

# Environment settings
@export var dynamic_lighting := true
@export var dynamic_fog := true
@export var ambient_sounds := true
@export var particle_effects := true

# Lighting variables
@export var day_night_cycle := false
@export var day_night_cycle_speed := 0.1
@export var sun_light_path: NodePath
@export var environment_path: NodePath
var sun_light: DirectionalLight3D
var world_environment: WorldEnvironment
var time_of_day := 0.5  # 0.0 = midnight, 0.5 = noon, 1.0 = midnight

# Fog variables
@export var fog_color_day := Color(0.8, 0.9, 1.0, 1.0)
@export var fog_color_night := Color(0.1, 0.15, 0.3, 1.0)
@export var fog_density_min := 0.001
@export var fog_density_max := 0.01
@export var fog_height_min := -10.0
@export var fog_height_max := 50.0
var fog_timer := 0.0
var fog_change_speed := 0.1

# Ambient sound variables
@export var ambient_sound_path: NodePath
@export var ambient_sound_volume := -10.0
@export var ambient_sound_fade_time := 2.0
var ambient_sound_player: AudioStreamPlayer
var ambient_sounds_list := []
var current_ambient_sound := -1
var ambient_sound_timer := 0.0
var ambient_sound_interval := 60.0  # Change ambient sound every minute

# Particle systems
@export var dust_particles_path: NodePath
@export var dust_density := 0.5
var dust_particles: GPUParticles3D
var player: Node3D

func _ready() -> void:
	# Get references
	if sun_light_path:
		sun_light = get_node(sun_light_path)
	
	if environment_path:
		world_environment = get_node(environment_path)
	
	if ambient_sound_path:
		ambient_sound_player = get_node(ambient_sound_path)
		if !ambient_sound_player:
			ambient_sound_player = AudioStreamPlayer.new()
			ambient_sound_player.name = "AmbientSoundPlayer"
			add_child(ambient_sound_player)
			ambient_sound_player.volume_db = ambient_sound_volume
			ambient_sound_player.bus = "Ambient"
	
	if dust_particles_path:
		dust_particles = get_node(dust_particles_path)
	
	# Find player
	player = get_tree().get_nodes_in_group("player")[0] if get_tree().get_nodes_in_group("player").size() > 0 else null
	
	# Setup ambient sounds
	setup_ambient_sounds()
	
	# Start with random time of day if cycle is enabled
	if day_night_cycle:
		time_of_day = randf()

func _process(delta: float) -> void:
	# Update day/night cycle
	if day_night_cycle and sun_light and world_environment:
		update_day_night_cycle(delta)
	
	# Update fog
	if dynamic_fog and world_environment:
		update_fog(delta)
	
	# Update ambient sounds
	if ambient_sounds and ambient_sound_player:
		update_ambient_sounds(delta)
	
	# Update particle effects
	if particle_effects and dust_particles and player:
		update_particles()

func update_day_night_cycle(delta: float) -> void:
	# Update time of day
	time_of_day += delta * day_night_cycle_speed
	if time_of_day >= 1.0:
		time_of_day -= 1.0
	
	# Calculate sun angle
	var sun_angle = time_of_day * TAU
	sun_light.rotation.x = sun_angle - PI/2
	
	# Calculate sun energy based on time of day
	var sun_height = sin(sun_angle)
	sun_light.light_energy = max(0.0, sun_height) * 1.5
	
	# Update environment based on time of day
	if world_environment and world_environment.environment:
		var env = world_environment.environment
		
		# Adjust ambient light
		var ambient_energy = clamp(sun_height * 0.5 + 0.5, 0.2, 1.0)
		env.ambient_light_energy = ambient_energy
		
		# Adjust ambient light color
		var day_color = Color(1.0, 1.0, 1.0)
		var night_color = Color(0.2, 0.3, 0.5)
		env.ambient_light_color = day_color.lerp(night_color, clamp(1.0 - sun_height, 0.0, 1.0))
		
		# Adjust sky
		if env.sky:
			env.sky_energy = clamp(sun_height * 0.5 + 0.5, 0.2, 1.0)

func update_fog(delta: float) -> void:
	if !world_environment or !world_environment.environment:
		return
	
	var env = world_environment.environment
	
	# Update fog timer
	fog_timer += delta * fog_change_speed
	
	# Calculate fog density with some variation
	var fog_density = fog_density_min + (fog_density_max - fog_density_min) * (0.5 + 0.5 * sin(fog_timer * 0.1))
	
	# Calculate fog height with some variation
	var fog_height = fog_height_min + (fog_height_max - fog_height_min) * (0.5 + 0.5 * sin(fog_timer * 0.05))
	
	# Set fog properties
	env.fog_enabled = true
	env.fog_density = fog_density
	env.fog_height = fog_height
	
	# Adjust fog color based on time of day if day/night cycle is enabled
	if day_night_cycle:
		var sun_height = sin(time_of_day * TAU)
		env.fog_color = fog_color_day.lerp(fog_color_night, clamp(1.0 - sun_height, 0.0, 1.0))

func setup_ambient_sounds() -> void:
	# This would typically load ambient sound resources
	# For now, we'll just print that it would happen
	print("Ambient sounds would be loaded here")
	
	# In a real implementation, you would do something like:
	# ambient_sounds_list.append(preload("res://sounds/ambient/wind.ogg"))
	# ambient_sounds_list.append(preload("res://sounds/ambient/forest.ogg"))
	# etc.

func update_ambient_sounds(delta: float) -> void:
	if ambient_sounds_list.size() == 0:
		return
	
	# Update ambient sound timer
	ambient_sound_timer += delta
	
	# Change ambient sound periodically
	if ambient_sound_timer >= ambient_sound_interval or current_ambient_sound == -1:
		ambient_sound_timer = 0.0
		
		# Choose a new ambient sound
		var new_sound_index = randi() % ambient_sounds_list.size()
		while new_sound_index == current_ambient_sound and ambient_sounds_list.size() > 1:
			new_sound_index = randi() % ambient_sounds_list.size()
		
		current_ambient_sound = new_sound_index
		
		# Fade out current sound and fade in new sound
		if ambient_sound_player.playing:
			var tween = create_tween()
			tween.tween_property(ambient_sound_player, "volume_db", -40.0, ambient_sound_fade_time)
			tween.tween_callback(func():
				ambient_sound_player.stream = ambient_sounds_list[current_ambient_sound]
				ambient_sound_player.play()
				var new_tween = create_tween()
				new_tween.tween_property(ambient_sound_player, "volume_db", ambient_sound_volume, ambient_sound_fade_time)
			)

func update_particles() -> void:
	if !dust_particles:
		return
	
	# Position dust particles near player
	dust_particles.global_position = player.global_position
	
	# Adjust emission based on player movement
	var player_speed = player.velocity.length()
	var emission_rate = dust_density * clamp(player_speed / 10.0, 0.1, 2.0)
	
	# Update particle emission
	if dust_particles.amount_ratio != emission_rate:
		dust_particles.amount_ratio = emission_rate	
