extends Node
class_name PlayerSoundManager

# References to audio players
@onready var footstep_player: AudioStreamPlayer3D = $FootstepPlayer
@onready var jump_player: AudioStreamPlayer3D = $JumpPlayer
@onready var land_player: AudioStreamPlayer3D = $LandPlayer
@onready var dash_player: AudioStreamPlayer3D = $DashPlayer
@onready var slide_player: AudioStreamPlayer3D = $SlidePlayer
@onready var grapple_shoot_player: AudioStreamPlayer3D = $GrappleShootPlayer
@onready var grapple_pull_player: AudioStreamPlayer3D = $GrapplePullPlayer
@onready var damage_player: AudioStreamPlayer3D = $DamagePlayer
@onready var heal_player: AudioStreamPlayer3D = $HealPlayer
@onready var death_player: AudioStreamPlayer3D = $DeathPlayer

# Sound resources
var footstep_sounds: Array[AudioStream] = []
var metal_footstep_sounds: Array[AudioStream] = []
var concrete_footstep_sounds: Array[AudioStream] = []
var grass_footstep_sounds: Array[AudioStream] = []

var jump_sound: AudioStream
var land_sound: AudioStream
var dash_sound: AudioStream
var dash_recharge_sound: AudioStream
var slide_sound: AudioStream
var slide_concrete_sound: AudioStream
var slide_metal_sound: AudioStream
var grapple_shoot_sound: AudioStream
var grapple_pull_sound: AudioStream
var damage_sound: AudioStream
var heal_sound: AudioStream
var death_sound: AudioStream
var bhop_sound: AudioStream
var slide_jump_sound: AudioStream
var grapple_jump_sound: AudioStream

# Sound parameters
var footstep_pitch_range := Vector2(0.9, 1.1)
var footstep_volume_range := Vector2(-15.0, -10.0)
var last_footstep_index := -1

func _ready() -> void:
	# Load footstep sounds
	for i in range(1, 5):  # Assuming you have 4 footstep sounds
		var sound_path = "res://sounds/player/footsteps/footstep_%02d.wav" % i
		var sound = load(sound_path)
		if sound:
			footstep_sounds.append(sound)
	
	# Load metal footstep sounds
	for i in range(1, 5):
		var sound_path = "res://sounds/player/footsteps/metal/metal_footstep_%02d.wav" % i
		var sound = load(sound_path)
		if sound:
			metal_footstep_sounds.append(sound)
	
	# Load concrete footstep sounds
	for i in range(1, 5):
		var sound_path = "res://sounds/player/footsteps/concrete/concrete_footstep_%02d.wav" % i
		var sound = load(sound_path)
		if sound:
			concrete_footstep_sounds.append(sound)
	
	# Load grass footstep sounds
	for i in range(1, 5):
		var sound_path = "res://sounds/player/footsteps/grass/grass_footstep_%02d.wav" % i
		var sound = load(sound_path)
		if sound:
			grass_footstep_sounds.append(sound)
	
	# Load other sounds
	jump_sound = load("res://sounds/player/movement/jump.wav")
	land_sound = load("res://sounds/player/movement/land.wav")
	dash_sound = load("res://sounds/player/movement/dash.wav")
	dash_recharge_sound = load("res://sounds/player/movement/dash_recharge.wav")
	slide_sound = load("res://sounds/player/movement/slide.wav")
	slide_concrete_sound = load("res://sounds/player/movement/slide_concrete.wav")
	slide_metal_sound = load("res://sounds/player/movement/slide_metal.wav")
	grapple_shoot_sound = load("res://sounds/player/grapple/grapple_shoot.wav")
	grapple_pull_sound = load("res://sounds/player/grapple/grapple_pull.wav")
	damage_sound = load("res://sounds/player/damage.wav")
	heal_sound = load("res://sounds/player/heal.wav")
	death_sound = load("res://sounds/player/death.wav")
	bhop_sound = load("res://sounds/player/movement/bhop.wav")
	slide_jump_sound = load("res://sounds/player/movement/slide_jump.wav")
	grapple_jump_sound = load("res://sounds/player/movement/grapple_jump.wav")
	
	# Assign sounds to players
	if jump_sound:
		jump_player.stream = jump_sound
	if land_sound:
		land_player.stream = land_sound
	if dash_sound:
		dash_player.stream = dash_sound
	if slide_sound:
		slide_player.stream = slide_sound
	if grapple_shoot_sound:
		grapple_shoot_player.stream = grapple_shoot_sound
	if grapple_pull_sound:
		grapple_pull_player.stream = grapple_pull_sound
	if damage_sound:
		damage_player.stream = damage_sound
	if heal_sound:
		heal_player.stream = heal_sound
	if death_sound:
		death_player.stream = death_sound

# Play a random footstep sound
func play_footstep() -> void:
	if footstep_sounds.size() == 0 or !footstep_player:
		return
	
	# Choose a random footstep sound that's different from the last one
	var index = randi() % footstep_sounds.size()
	while index == last_footstep_index and footstep_sounds.size() > 1:
		index = randi() % footstep_sounds.size()
	
	last_footstep_index = index
	
	# Set random pitch and volume
	footstep_player.pitch_scale = randf_range(footstep_pitch_range.x, footstep_pitch_range.y)
	footstep_player.volume_db = randf_range(footstep_volume_range.x, footstep_volume_range.y)
	
	# Set the stream and play
	footstep_player.stream = footstep_sounds[index]
	footstep_player.play()

# Play footstep sound based on surface type
func play_footstep_on_surface(surface_type: String) -> void:
	if !footstep_player:
		return
	
	var sounds_to_use = footstep_sounds
	
	# Select the appropriate sound array based on surface type
	match surface_type:
		"metal":
			if metal_footstep_sounds.size() > 0:
				sounds_to_use = metal_footstep_sounds
		"concrete":
			if concrete_footstep_sounds.size() > 0:
				sounds_to_use = concrete_footstep_sounds
		"grass":
			if grass_footstep_sounds.size() > 0:
				sounds_to_use = grass_footstep_sounds
	
	if sounds_to_use.size() == 0:
		return
	
	# Choose a random sound that's different from the last one
	var index = randi() % sounds_to_use.size()
	while index == last_footstep_index and sounds_to_use.size() > 1:
		index = randi() % sounds_to_use.size()
	
	last_footstep_index = index
	
	# Set random pitch and volume
	footstep_player.pitch_scale = randf_range(footstep_pitch_range.x, footstep_pitch_range.y)
	footstep_player.volume_db = randf_range(footstep_volume_range.x, footstep_volume_range.y)
	
	# Set the stream and play
	footstep_player.stream = sounds_to_use[index]
	footstep_player.play()

# Play jump sound
func play_jump() -> void:
	if jump_player and jump_sound:
		jump_player.pitch_scale = randf_range(0.95, 1.05)
		jump_player.play()

# Play special bhop sound
func play_bhop() -> void:
	if jump_player and bhop_sound:
		jump_player.stream = bhop_sound
		jump_player.pitch_scale = randf_range(0.95, 1.05)
		jump_player.play()
		
		# Reset to normal jump sound after playing
		await jump_player.finished
		jump_player.stream = jump_sound

# Play slide jump sound
func play_slide_jump() -> void:
	if jump_player and slide_jump_sound:
		jump_player.stream = slide_jump_sound
		jump_player.pitch_scale = 0.8
		jump_player.play()
		
		# Reset to normal jump sound after playing
		await jump_player.finished
		jump_player.stream = jump_sound

# Play grapple jump sound
func play_grapple_jump() -> void:
	if jump_player and grapple_jump_sound:
		jump_player.stream = grapple_jump_sound
		jump_player.pitch_scale = 1.2
		jump_player.play()
		
		# Reset to normal jump sound after playing
		await jump_player.finished
		jump_player.stream = jump_sound

# Play landing sound
func play_land(intensity: float = 1.0) -> void:
	if land_player and land_sound:
		land_player.pitch_scale = randf_range(0.95, 1.05)
		land_player.volume_db = -15.0 + (intensity * 10.0)  # Louder for harder landings
		land_player.play()

# Play dash sound
func play_dash() -> void:
	if dash_player and dash_sound:
		dash_player.pitch_scale = randf_range(0.95, 1.05)
		dash_player.play()

# Play dash recharge sound
func play_dash_recharge() -> void:
	if dash_player and dash_recharge_sound:
		dash_player.stream = dash_recharge_sound
		dash_player.pitch_scale = 1.5
		dash_player.volume_db = -10.0
		dash_player.play()
		
		# Reset to normal dash sound after playing
		await dash_player.finished
		dash_player.stream = dash_sound
		dash_player.volume_db = 0.0

# Play slide sound
func play_slide() -> void:
	if slide_player and slide_sound:
		slide_player.pitch_scale = randf_range(0.95, 1.05)
		slide_player.stream = slide_sound
		slide_player.play()

# Play slide sound based on surface
func play_slide_on_surface(surface_type: String) -> void:
	if !slide_player:
		return
	
	var sound_to_use = slide_sound
	
	# Select the appropriate sound based on surface type
	match surface_type:
		"metal":
			if slide_metal_sound:
				sound_to_use = slide_metal_sound
		"concrete":
			if slide_concrete_sound:
				sound_to_use = slide_concrete_sound
	
	if sound_to_use:
		slide_player.pitch_scale = randf_range(0.95, 1.05)
		slide_player.stream = sound_to_use
		slide_player.play()

# Stop slide sound with fade out
func stop_slide() -> void:
	if slide_player and slide_player.playing:
		var tween = create_tween()
		tween.tween_property(slide_player, "volume_db", -40.0, 0.2)
		tween.tween_callback(slide_player.stop)
		tween.tween_property(slide_player, "volume_db", 0.0, 0.0)

# Play grapple shoot sound
func play_grapple_shoot() -> void:
	if grapple_shoot_player and grapple_shoot_sound:
		grapple_shoot_player.pitch_scale = randf_range(0.95, 1.05)
		grapple_shoot_player.play()

# Play grapple pull sound (looping)
func play_grapple_pull() -> void:
	if grapple_pull_player and grapple_pull_sound:
		if !grapple_pull_player.playing:
			grapple_pull_player.play()

# Stop grapple pull sound with fade out
func stop_grapple_pull() -> void:
	if grapple_pull_player and grapple_pull_player.playing:
		var tween = create_tween()
		tween.tween_property(grapple_pull_player, "volume_db", -40.0, 0.2)
		tween.tween_callback(grapple_pull_player.stop)
		tween.tween_property(grapple_pull_player, "volume_db", 0.0, 0.0)

# Play a failed grapple sound
func play_failed_grapple() -> void:
	if grapple_shoot_player and grapple_shoot_sound:
		grapple_shoot_player.pitch_scale = 0.7
		grapple_shoot_player.volume_db = -10.0
		grapple_shoot_player.play()
		
		# Reset for next time
		await grapple_shoot_player.finished
		grapple_shoot_player.pitch_scale = 1.0
		grapple_shoot_player.volume_db = 0.0

# Play damage sound
func play_damage(amount: float) -> void:
	if damage_player and damage_sound:
		# Adjust pitch based on damage amount
		damage_player.pitch_scale = 1.0 + clamp(amount / 50.0, 0.0, 0.5)
		damage_player.play()

# Play heal sound
func play_heal() -> void:
	if heal_player and heal_sound:
		heal_player.pitch_scale = randf_range(0.95, 1.05)
		heal_player.play()

# Play death sound
func play_death() -> void:
	if death_player and death_sound:
		death_player.play()
