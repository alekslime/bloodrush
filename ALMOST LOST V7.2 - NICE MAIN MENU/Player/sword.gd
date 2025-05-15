extends Node3D
class_name Sword

# =============================================
# EXPORTED PROPERTIES
# =============================================
# Basic sword properties
@export_group("Basic Properties")
@export var damage := 25.0                    # Base damage for normal attacks
@export var heavy_damage_multiplier := 2.0    # Multiplier for heavy attacks
@export var critical_chance := 0.15           # 15% chance for critical hits
@export var critical_multiplier := 1.5        # 50% more damage on critical hits

# Timing properties
@export_group("Timing Properties")
@export var swing_speed := 0.3                # Duration of normal swing animation
@export var heavy_swing_speed := 0.6          # Duration of heavy swing animation
@export var swing_cooldown := 0.2             # Cooldown between normal swings
@export var heavy_swing_cooldown := 0.5       # Cooldown between heavy swings
@export var combo_timeout := 1.2              # Time before combo resets

# Range and angle properties
@export_group("Range Properties")
@export var swing_range := 2.5                # Attack range for normal swings
@export var heavy_swing_range := 3.0          # Attack range for heavy swings
@export var swing_angle := 70.0               # Attack angle in degrees (how wide the swing is)

# Movement-based damage modifiers
@export_group("Movement Modifiers")
@export var dash_damage_multiplier := 1.5     # Damage multiplier when dashing
@export var slide_damage_multiplier := 1.8    # Damage multiplier when sliding
@export var air_damage_multiplier := 1.3      # Damage multiplier when in air
@export var grapple_damage_multiplier := 2.0  # Damage multiplier when grappling

# Visual and feedback properties
@export_group("Visual Properties")
@export var sword_trail_duration := 0.3       # How long the sword trail lasts
@export var sword_trail_width := 0.1          # Width of the sword trail
@export var hit_impulse_strength := 10.0      # Force applied to physics objects when hit



# =============================================
# INTERNAL VARIABLES
# =============================================
# Sword state tracking
var is_swinging := false                      # Whether the sword is currently swinging
var can_swing := true                         # Whether the sword can start a new swing
var swing_timer := 0.0                        # Timer for current swing duration
var cooldown_timer := 0.0                     # Timer for cooldown between swings
var is_heavy_attack := false                  # Whether current attack is heavy
var current_combo := 0                        # Current combo counter (0-3)
var max_combo := 3                            # Maximum combo count
var combo_timer := 0.0                        # Timer for combo timeout
var last_hit_time := 0.0                      # Time of last successful hit
var hit_enemies := []                         # Array to track enemies hit in current swing

# Visual effect variables
var trail_points := []                        # Points for sword trail
var trail_times := []                         # Timestamps for trail points
var trail_active := false                     # Whether trail is currently active

# =============================================
# NODE REFERENCES
# =============================================
# These will be assigned in _ready()
@onready var sword_model: Node3D = $SwordModel
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var swing_sound: AudioStreamPlayer3D = $SwingSound
@onready var hit_sound: AudioStreamPlayer3D = $HitSound
@onready var critical_sound: AudioStreamPlayer3D = $CriticalSound
@onready var collision_shape: CollisionShape3D = $HitArea/CollisionShape3D
@onready var hit_area: Area3D = $HitArea
@onready var hit_particles: GPUParticles3D = $HitParticles
@onready var sword_trail: MeshInstance3D = $SwordTrail
@onready var blade_tip: Marker3D = $SwordModel/BladeTip
@onready var blade_base: Marker3D = $SwordModel/BladeBase

# Reference to player controller
var player: MovementController = null

# =============================================
# INITIALIZATION
# =============================================
func _ready() -> void:
	
	hitbox.add_to_group("player_weapon")
	# Get reference to player (parent of parent)
	player = get_parent().get_parent() as MovementController
	
	# Verify we have the player reference
	if !player:
		push_error("Sword could not find player reference!")
	
	# Setup hit area connections
	hit_area.connect("body_entered", _on_hit_area_body_entered)
	
	# Initially disable collision
	collision_shape.disabled = true
	
	# Hide particles initially
	hit_particles.emitting = false
	
	# Setup sword trail
	setup_sword_trail()
	
	# Add to weapons group for easy access
	add_to_group("weapons")
	
	# Print debug info
	print("Sword initialized with damage: ", damage)

# =============================================
# MAIN PROCESS FUNCTIONS
# =============================================
func _process(delta: float) -> void:
	# Handle combo timer
	if current_combo > 0:
		combo_timer += delta
		if combo_timer >= combo_timeout:
			# Reset combo if timeout reached
			current_combo = 0
			combo_timer = 0.0
			print("Combo reset due to timeout")
	
	# Handle cooldown
	if !can_swing:
		cooldown_timer += delta
		var current_cooldown = heavy_swing_cooldown if is_heavy_attack else swing_cooldown
		if cooldown_timer >= current_cooldown:
			can_swing = true
			cooldown_timer = 0.0
	
	# Handle active swing
	if is_swinging:
		swing_timer += delta
		var swing_duration = heavy_swing_speed if is_heavy_attack else swing_speed
		
		# Update sword trail during swing
		if trail_active:
			update_sword_trail()
		
		# End swing when duration is reached
		if swing_timer >= swing_duration:
			end_swing()
	
	# Process sword trail fade-out
	process_sword_trail(delta)
	
	# Check for swing input
	check_input()

# =============================================
# INPUT HANDLING
# =============================================
func check_input() -> void:
	# Primary attack (normal swing)
	if Input.is_action_just_pressed("primary_attack") and can_swing and !is_swinging:
		start_swing(false)
	
	# Secondary attack (heavy swing)
	if Input.is_action_just_pressed("secondary_attack") and can_swing and !is_swinging:
		start_swing(true)

# =============================================
# SWORD SWING MECHANICS
# =============================================
func start_swing(heavy: bool) -> void:
	is_swinging = true
	can_swing = false
	is_heavy_attack = heavy
	swing_timer = 0.0
	cooldown_timer = 0.0
	hit_enemies.clear()  # Clear the hit enemies array for new swing
	
	# Increment combo for regular attacks
	if !heavy:
		current_combo = (current_combo + 1) % (max_combo + 1)
		if current_combo == 0:
			current_combo = 1
		combo_timer = 0.0
		print("Starting combo: ", current_combo)
	else:
		# Heavy attacks reset combo
		current_combo = 0
		print("Starting heavy attack")
	
	# Play appropriate animation
	var anim_name = "heavy_swing" if heavy else "swing_" + str(current_combo)
	if animation_player.has_animation(anim_name):
		animation_player.play(anim_name)
	else:
		# Fallback animation
		animation_player.play("swing_1")
		print("Animation not found: ", anim_name, ", using fallback")
	
	# Play sound with slight pitch variation for variety
	swing_sound.pitch_scale = 0.8 if heavy else (1.0 + randf_range(-0.1, 0.1))
	swing_sound.play()
	
	# Enable collision
	collision_shape.disabled = false
	
	# Adjust collision shape based on attack type
	var attack_range = heavy_swing_range if heavy else swing_range
	if collision_shape.shape is BoxShape3D:
		# Update box shape size and position
		collision_shape.shape.size.z = attack_range
		collision_shape.position.z = -attack_range / 2
	
	# Start sword trail
	start_sword_trail()
	
	# Apply slight camera shake for feedback
	if player and player.head and player.head.has_method("add_camera_shake"):
		var shake_amount = 0.2 if heavy else 0.1
		player.head.add_camera_shake(shake_amount, 0.2)

func end_swing() -> void:
	is_swinging = false
	swing_timer = 0.0
	
	# Disable collision
	collision_shape.disabled = true
	
	# End sword trail
	end_sword_trail()
	
	# Reset sword position
	if animation_player.has_animation("idle"):
		animation_player.play("idle")
	
	print("Swing ended")

# =============================================
# COLLISION AND DAMAGE HANDLING
# =============================================
func _on_hit_area_body_entered(body: Node3D) -> void:
	# Skip if we already hit this enemy in this swing
	if body in hit_enemies:
		return
	
	# Add to hit enemies array to prevent multiple hits in same swing
	hit_enemies.append(body)
	
	# Check if we hit an enemy
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		# Calculate damage based on attack type and player state
		var final_damage = calculate_damage(body)
		
		# Apply damage to enemy
		body.take_damage(final_damage)
		
		# Record hit time
		last_hit_time = Time.get_ticks_msec() / 1000.0
		
		# Play hit sound with random pitch for variety
		hit_sound.pitch_scale = randf_range(0.9, 1.1)
		hit_sound.play()
		
		# Show hit particles at hit position
		position_hit_particles(body)
		
		# Apply force to enemy if it has a physics body
		apply_hit_force(body)
		
		# Trigger hit stop (game freeze) for impactful feedback
		trigger_hit_stop()
		
		print("Hit enemy with damage: ", final_damage)

# Calculate final damage based on various factors
func calculate_damage(body: Node3D) -> float:
	var final_damage = damage
	
	# Apply attack type multiplier
	if is_heavy_attack:
		final_damage *= heavy_damage_multiplier
	
	# Apply movement-based damage multipliers
	if player.is_dashing:
		final_damage *= dash_damage_multiplier
	elif player.is_sliding:
		final_damage *= slide_damage_multiplier
	elif player.is_grappling:
		final_damage *= grapple_damage_multiplier
	elif !player.is_on_floor():
		final_damage *= air_damage_multiplier
	
	# Check for critical hit
	if randf() <= critical_chance:
		final_damage *= critical_multiplier
		# Play critical hit sound
		if critical_sound:
			critical_sound.play()
		print("Critical hit!")
	
	return final_damage

# Position hit particles at the hit location
func position_hit_particles(body: Node3D) -> void:
	# Get hit position (use body center if no better option)
	var hit_pos = body.global_position
	
	# If body has a collision shape, use that for better position
	if body.has_node("CollisionShape3D"):
		var col_shape = body.get_node("CollisionShape3D")
		hit_pos = col_shape.global_position
	
	# Position particles
	hit_particles.global_position = hit_pos
	hit_particles.emitting = true

# Apply physical force to hit objects
func apply_hit_force(body: Node3D) -> void:
	# Apply force to physics bodies
	if body is RigidBody3D:
		var direction = (body.global_position - global_position).normalized()
		var force = direction * hit_impulse_strength * (2.0 if is_heavy_attack else 1.0)
		body.apply_central_impulse(force)
	
	# For character bodies, we can apply knockback if they have a method for it
	elif body is CharacterBody3D and body.has_method("apply_knockback"):
		var direction = (body.global_position - global_position).normalized()
		var strength = hit_impulse_strength * (2.0 if is_heavy_attack else 1.0)
		body.apply_knockback(direction, strength)

# Create a brief pause for hit impact
func trigger_hit_stop() -> void:
	# This would ideally be implemented in a game manager
	# For now, we'll just print that it would happen
	print("Hit stop triggered")
	
	# If you have a time scale manager, you could do something like:
	# TimeManager.set_time_scale(0.05, 0.1) # Slow to 5% for 0.1 seconds

# =============================================
# SWORD TRAIL EFFECTS
# =============================================
func setup_sword_trail() -> void:
	# Skip if no sword trail mesh
	if !sword_trail:
		return
	
	# Initialize empty trail
	trail_points = []
	trail_times = []
	trail_active = false
	
	# Hide trail initially
	sword_trail.visible = false

func start_sword_trail() -> void:
	# Skip if no sword trail mesh
	if !sword_trail:
		return
	
	# Clear previous trail
	trail_points = []
	trail_times = []
	trail_active = true
	
	# Show trail
	sword_trail.visible = true

func update_sword_trail() -> void:
	# Skip if trail not active or missing components
	if !trail_active or !sword_trail or !blade_tip or !blade_base:
		return
	
	# Get current time
	var current_time = Time.get_ticks_msec() / 1000.0
	
	# Add new points to trail
	trail_points.append(blade_tip.global_position)
	trail_times.append(current_time)
	
	# Add base point too for width
	trail_points.append(blade_base.global_position)
	trail_times.append(current_time)
	
	# Update trail mesh
	update_trail_mesh()

func end_sword_trail() -> void:
	trail_active = false

func process_sword_trail(delta: float) -> void:
	# Skip if no trail or no points
	if !sword_trail or trail_points.size() == 0:
		return
	
	# Get current time
	var current_time = Time.get_ticks_msec() / 1000.0
	
	# Remove old points
	var i = 0
	while i < trail_times.size():
		if current_time - trail_times[i] > sword_trail_duration:
			trail_times.remove_at(i)
			trail_points.remove_at(i)
		else:
			i += 1
	
	# Hide trail if no points left
	if trail_points.size() == 0:
		sword_trail.visible = false
	else:
		# Update trail mesh
		update_trail_mesh()

func update_trail_mesh() -> void:
	# This is a simplified version - in a real implementation,
	# you would create a proper mesh with vertices, indices, etc.
	# For now, we'll just print that it would update
	print("Trail mesh updated with ", trail_points.size(), " points")
	
	# In a real implementation, you would do something like:
	# var mesh = ArrayMesh.new()
	# var vertices = PackedVector3Array()
	# var colors = PackedColorArray()
	# ... add vertices and colors based on trail_points and trail_times
	# ... create mesh surface
	# sword_trail.mesh = mesh
