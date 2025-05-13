extends Node3D
class_name VisualEffects

# Effect settings
@export var screen_effects := true
@export var motion_blur := true
@export var chromatic_aberration := true
@export var vignette := true

# Screen effect variables
@export var environment_path: NodePath
var world_environment: WorldEnvironment
var motion_blur_strength := 0.0
var chromatic_strength := 0.0
var vignette_strength := 0.3

# Player reference
var player: MovementController

func _ready() -> void:
	# Get environment reference
	if environment_path:
		world_environment = get_node(environment_path)
	
	# Find player
	player = get_tree().get_nodes_in_group("player")[0] if get_tree().get_nodes_in_group("player").size() > 0 else null
	
	# Initialize effects
	if world_environment and world_environment.environment:
		setup_screen_effects()

func _process(delta: float) -> void:
	if !screen_effects or !world_environment or !world_environment.environment or !player:
		return
	
	# Update screen effects based on player state
	update_screen_effects(delta)

func setup_screen_effects() -> void:
	var env = world_environment.environment
	
	# Setup motion blur
	if motion_blur:
		# This would typically set up a motion blur shader
		# For now, we'll just print that it would happen
		print("Motion blur would be set up here")
	
	# Setup chromatic aberration
	if chromatic_aberration:
		# This would typically set up a chromatic aberration shader
		print("Chromatic aberration would be set up here")
	
	# Setup vignette
	if vignette:
		# This would typically set up a vignette effect
		print("Vignette would be set up here")

func update_screen_effects(delta: float) -> void:
	var env = world_environment.environment
	
	# Calculate target effect strengths based on player state
	var target_motion_blur = 0.0
	var target_chromatic = 0.0
	var target_vignette = 0.3  # Base vignette strength
	
	# Adjust effects based on player state
	if player.is_dashing:
		target_motion_blur = 0.5
		target_chromatic = 0.3
		target_vignette = 0.5
	elif player.is_sliding:
		target_motion_blur = 0.3
		target_chromatic = 0.2
		target_vignette = 0.4
	elif player.is_grappling:
		target_motion_blur = 0.4
		target_chromatic = 0.25
		target_vignette = 0.45
	else:
		# Base effects on player speed
		var speed_factor = clamp(player.velocity.length() / player.speed, 0.0, 1.0)
		target_motion_blur = speed_factor * 0.2
		target_chromatic = speed_factor * 0.1
	
	# Smoothly interpolate effect strengths
	motion_blur_strength = lerp(motion_blur_strength, target_motion_blur, delta * 5.0)
	chromatic_strength = lerp(chromatic_strength, target_chromatic, delta * 5.0)
	vignette_strength = lerp(vignette_strength, target_vignette, delta * 5.0)
	
	# Apply effect strengths
	# In a real implementation, you would update shader parameters here
	# For now, we'll just print the values
	if motion_blur_strength > 0.01 or chromatic_strength > 0.01 or vignette_strength > 0.01:
		print("Motion blur: ", motion_blur_strength, ", Chromatic: ", chromatic_strength, ", Vignette: ", vignette_strength)
