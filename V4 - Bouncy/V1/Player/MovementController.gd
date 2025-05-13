extends CharacterBody3D
class_name MovementController

@export var max_health := 100.0
var current_health := max_health

# Basic movement parameters
@export var gravity_multiplier := 5.0
@export var speed := 45
@export var acceleration := 25
@export var deceleration := 25
@export_range(0.0, 1.0, 0.05) var air_control := 2.0
@export var jump_height := 15

# Dash parameters - Now with limited dashes
@export var dash_speed := 180.0
@export var dash_duration := 0.2
@export var dash_cooldown := 0.5
@export var max_dashes := 3  # Maximum number of dashes
var dash_count := max_dashes  # Current number of dashes available
var dash_recharge_timer := 0.0
@export var dash_recharge_time := 1.0  # Time to recharge one dash
var can_dash := true
var is_dashing := false
var dash_timer := 0.0
var dash_cooldown_timer := 0.0
var dash_direction := Vector3.ZERO
var was_dashing := false  # Track if player was just dashing (for bunny hop control)

# ULTRAKILL-style slide parameters
@export var slide_speed := 100.0
@export var slide_duration := 1.3
@export var slide_boost := 5.0
@export var slide_friction := 0.05
var is_sliding := false
var slide_timer := 0.0
var slide_direction := Vector3.ZERO
var was_sliding := false  # Track if player was just sliding (for bunny hop control)

# Bunny hop parameters
@export var bhop_boost := 5.5 # Boost factor for slide bunny hops
var bhop_window := 0.2  # Time window to perform a bunny hop after slide
var bhop_timer := 0.0  # Timer for bunny hop window

# Grapple parameters
@export var grapple_max_distance := 101.0
@export var grapple_pull_speed := 150.0
@export var grapple_swing_influence := 0.2
@export var grapple_cooldown := 0.5
@export var grapple_break_distance := 2.0  # How close to target before breaking
var can_grapple := true
var is_grappling := false
var grapple_point := Vector3.ZERO
var grapple_normal := Vector3.ZERO
var grapple_cooldown_timer := 0.0
var grapple_object: Node3D = null
var grapple_length := 0.0

# Grapple rope visual
var rope_segments := 8  # Number of rope segments
var rope_segment_meshes := []  # Array to hold segment meshes
var rope_material: StandardMaterial3D
var hook_mesh: MeshInstance3D

# Reference to head node for camera control
@onready var head: Node3D = $Head  # Make sure this path matches your scene structure

# Reference to raycast for grapple detection
@onready var grapple_raycast: RayCast3D = $Head/Camera/GrappleRaycast

var direction := Vector3()
var input_axis := Vector2()
var original_height := 0.0
var slide_height := 0.0

# Get the gravity from the project settings to be synced with RigidDynamicBody nodes.
@onready var gravity: float = (ProjectSettings.get_setting("physics/3d/default_gravity") 
	* gravity_multiplier)
@onready var collision_shape: CollisionShape3D = $CollisionShape  # Reference to collision shape

# UI elements for dash counter
@onready var dash_counter_label: Label = $UI/DashCounterLabel if has_node("UI/DashCounterLabel") else null

#Sword
@onready var anim_player = $Head/AnimationPlayer
#Hitbox
@onready var hitbox = $Head/Camera/WeaponPivot/WeaponMesh/Sketchfab_Scene/Hitbox


func _ready() -> void:
	# Store original height for later use
	original_height = collision_shape.shape.height if collision_shape.shape is CapsuleShape3D else 2.0
	slide_height = original_height * 0.5  # Half height during slide

	# Initialize dash counter UI if it exists
	update_dash_counter()

	# Setup grapple rope visual
	setup_grapple_rope()

	# Ensure the raycast exists
	if !grapple_raycast:
		grapple_raycast = RayCast3D.new()
		$Head/Camera.add_child(grapple_raycast)
		grapple_raycast.enabled = true
		grapple_raycast.target_position = Vector3(0, 0, -grapple_max_distance)
		grapple_raycast.collision_mask = 1  # Adjust to your collision layers
	
	# Add to player group for enemy targeting
	add_to_group("player")



func _process(delta: float) -> void:
	if Input.is_action_just_pressed("attack"):
		anim_player.play("attack")
		hitbox.monitoring = true

# Called every physics tick. 'delta' is constant
func _physics_process(delta: float) -> void:
	input_axis = Input.get_vector(&"move_back", &"move_forward",
			&"move_left", &"move_right")

	direction_input()

	# Track previous states for bunny hop logic
	was_dashing = is_dashing
	was_sliding = is_sliding

	# Handle dash mechanic with limited dashes
	handle_dash(delta)

	# Handle slide mechanic
	handle_slide(delta)

	# Handle grapple mechanic
	handle_grapple(delta)

	# Handle bunny hop timer
	if bhop_timer > 0:
		bhop_timer -= delta

	# Recharge dashes when on ground
	if is_on_floor() and dash_count < max_dashes and !is_dashing and !is_sliding:
		dash_recharge_timer += delta
		if dash_recharge_timer >= dash_recharge_time:
			dash_count += 1
			dash_recharge_timer = 0.0
			update_dash_counter()

	# Only apply normal movement if not dashing, sliding, or grappling
	if !is_dashing and !is_sliding and !is_grappling:
		if is_on_floor():
			if Input.is_action_just_pressed(&"jump"):
				handle_jump()
		else:
			velocity.y -= gravity * delta
		
		accelerate(delta)
	elif is_grappling:
		# Apply modified gravity during grapple (reduced)
		if !is_on_floor():
			velocity.y -= (gravity * 0.3) * delta
	else:
		# Apply gravity when in air during slide (but not during dash)
		if !is_on_floor() and is_sliding and !is_dashing:
			velocity.y -= gravity * delta

	move_and_slide()

	# Check if we need to break the grapple after moving
	if is_grappling:
		var distance_to_point = global_position.distance_to(grapple_point)
		if distance_to_point < grapple_break_distance:
			end_grapple()

func direction_input() -> void:
	direction = Vector3()
	var aim: Basis = get_global_transform().basis
	direction = aim.z * -input_axis.x + aim.x * input_axis.y

func accelerate(delta: float) -> void:
	# Using only the horizontal velocity, interpolate towards the input.
	var temp_vel := velocity
	temp_vel.y = 0

	var temp_accel: float
	var target: Vector3 = direction * speed

	if direction.dot(temp_vel) > 0:
		temp_accel = acceleration
	else:
		temp_accel = deceleration

	if not is_on_floor():
		temp_accel *= air_control

	var accel_weight = clamp(temp_accel * delta, 0.0, 1.0)
	temp_vel = temp_vel.lerp(target, accel_weight)

	velocity.x = temp_vel.x
	velocity.z = temp_vel.z

# Handle jump with bunny hop logic
func handle_jump() -> void:
	if was_sliding or bhop_timer > 0:
		# Slide bunny hop - preserve momentum and add boost
		velocity.y = jump_height
		
		# Apply horizontal boost in the direction of movement
		var current_dir = Vector3(velocity.x, 0, velocity.z).normalized()
		var current_speed = Vector3(velocity.x, 0, velocity.z).length()
		
		# Boost the speed for slide bunny hop
		velocity.x = current_dir.x * current_speed * bhop_boost
		velocity.z = current_dir.z * current_speed * bhop_boost
		
		# Start bunny hop window for chaining
		bhop_timer = bhop_window
	elif was_dashing:
		# Regular jump after dash - no momentum preservation
		velocity.y = jump_height
		# No horizontal boost for dash bunny hop
	else:
		# Regular jump
		velocity.y = jump_height

# Dash system with limited dashes
func handle_dash(delta: float) -> void:
	# Update dash cooldown timer
	if !can_dash:
		dash_cooldown_timer += delta
		if dash_cooldown_timer >= dash_cooldown:
			can_dash = true
			dash_cooldown_timer = 0.0

	# Handle active dash
	if is_dashing:
		dash_timer += delta
		if dash_timer >= dash_duration:
			is_dashing = false
			dash_timer = 0.0
			# Preserve some momentum after dash ends
			velocity = dash_direction * (dash_speed * 0.5)
		else:
			# During dash, maintain dash velocity
			velocity = dash_direction * dash_speed
			# No gravity during dash
			velocity.y = 0 if is_on_floor() else velocity.y

	# Initiate dash on input - Now with dash count limit
	if Input.is_action_just_pressed(&"dash") and can_dash and !is_sliding and dash_count > 0:
		if direction.length() > 0.1:
			dash_direction = direction.normalized()
		else:
			# Dash forward if no direction input
			dash_direction = -transform.basis.z.normalized()
		
		is_dashing = true
		can_dash = false
		dash_timer = 0.0
		dash_cooldown_timer = 0.0
		
		# Consume a dash
		dash_count -= 1
		update_dash_counter()
		
		# Apply immediate dash velocity
		velocity = dash_direction * dash_speed

func launch_from_jumppad(vertical_force: float, horizontal_force: Vector3 = Vector3.ZERO) -> void:
	# Override vertical velocity
	velocity.y = vertical_force
	
	# Add horizontal force if provided
	if horizontal_force != Vector3.ZERO:
		velocity.x = horizontal_force.x
		velocity.z = horizontal_force.z
	
	# Tell the head to add camera shake
	if head and head.has_method("add_camera_shake"):
		head.add_camera_shake(0.3, 0.2)

# SLIDE MECHANIC
func handle_slide(delta: float) -> void:
	# Start sliding - ULTRAKILL style
	if is_on_floor() and Input.is_action_just_pressed(&"slide") and !is_dashing and !is_sliding:
		start_ultrakill_slide()

	# Handle active slide
	if is_sliding:
		slide_timer += delta
		
		# ULTRAKILL slides maintain momentum with minimal friction
		if is_on_floor():
			# Apply very minimal friction for ULTRAKILL-like slide
			velocity.x = lerp(velocity.x, 0.0, slide_friction)
			velocity.z = lerp(velocity.z, 0.0, slide_friction)
			
			# Keep player grounded
			velocity.y = -0.1
		
		# Allow slight steering during slide (ULTRAKILL allows this)
		if direction.length() > 0.1:
			# Apply a small steering force
			var steer_force = direction.normalized() * 2.0
			velocity.x += steer_force.x * delta * 10
			velocity.z += steer_force.z * delta * 10
		
		# End slide if duration expired or player jumps
		if slide_timer >= slide_duration:
			end_slide()
		
		# Allow jumping out of slide with a boost (ULTRAKILL style)
		if Input.is_action_just_pressed(&"jump") and is_on_floor():
			velocity.y = jump_height * 1.2  # Boosted jump from slide
			bhop_timer = bhop_window  # Start bunny hop window
			end_slide()
		
		# Allow canceling slide early
		if Input.is_action_just_pressed(&"slide") and slide_timer > 0.2:
			end_slide()

# SLIDE START
func start_ultrakill_slide() -> void:
	is_sliding = true
	slide_timer = 0.0

	# Get current movement direction or use forward direction if not moving
	if velocity.length() > 3.0:
		slide_direction = velocity.normalized()
	else:
		slide_direction = -transform.basis.z.normalized()  # Forward direction

	# Calculate slide velocity - ULTRAKILL gives a strong initial boost
	var horizontal_speed = Vector3(velocity.x, 0, velocity.z).length()
	var boost_speed = max(horizontal_speed * slide_boost, slide_speed)

	# Apply the slide velocity
	velocity.x = slide_direction.x * boost_speed
	velocity.z = slide_direction.z * boost_speed

	# Lower player collision shape for sliding under obstacles
	if collision_shape.shape is CapsuleShape3D:
		collision_shape.shape.height = slide_height
		collision_shape.position.y = -0.5  # Adjust position to account for height change

	# Tell the head to lower camera for slide with tilt
	if head and head.has_method("tilt_for_slide"):
		head.tilt_for_slide(slide_direction)

func end_slide() -> void:
	is_sliding = false
	slide_timer = 0.0

	# Restore collision shape
	if collision_shape.shape is CapsuleShape3D:
		collision_shape.shape.height = original_height
		collision_shape.position.y = 0  # Reset position

	# Reset camera height and tilt
	if head and head.has_method("reset_from_slide"):
		head.reset_from_slide()

# Update UI for dash counter
func update_dash_counter() -> void:
	if dash_counter_label:
		dash_counter_label.text = "Dashes: " + str(dash_count) + "/" + str(max_dashes)

# Setup the rope mesh for grapple visualization
func setup_grapple_rope() -> void:
	# Clear any existing rope segments
	for segment in rope_segment_meshes:
		if is_instance_valid(segment):
			segment.queue_free()
	
	rope_segment_meshes.clear()
	
	# Create material for the rope with better visibility
	rope_material = StandardMaterial3D.new()
	rope_material.albedo_color = Color(0.9, 0.7, 0.2)  # Yellow-ish color
	rope_material.metallic = 0.7
	rope_material.roughness = 0.3
	
	# Add emission for better visibility
	rope_material.emission_enabled = true
	rope_material.emission = Color(0.9, 0.7, 0.2, 0.5)
	rope_material.emission_energy_multiplier = 0.5
	
	# Create segments
	for i in range(rope_segments):
		var segment = MeshInstance3D.new()
		segment.name = "RopeSegment" + str(i)
		add_child(segment)
		
		# Create a simple cylinder mesh for each segment
		var cylinder = CylinderMesh.new()
		cylinder.top_radius = 0.02
		cylinder.bottom_radius = 0.02
		cylinder.height = 1.0  # Will be scaled dynamically
		cylinder.radial_segments = 8
		
		segment.mesh = cylinder
		segment.material_override = rope_material
		segment.visible = false
		
		rope_segment_meshes.append(segment)
	
	# Create a hook at the end
	hook_mesh = MeshInstance3D.new()
	hook_mesh.name = "GrappleHook"
	add_child(hook_mesh)
	
	# Create a simple cone for the hook
	var cone = CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.05
	cone.height = 0.15
	
	hook_mesh.mesh = cone
	hook_mesh.material_override = rope_material
	hook_mesh.visible = false

# Handle grapple mechanics
func handle_grapple(delta: float) -> void:
	# Update grapple cooldown
	if !can_grapple:
		grapple_cooldown_timer += delta
		if grapple_cooldown_timer >= grapple_cooldown:
			can_grapple = true
			grapple_cooldown_timer = 0.0

	# Check for grapple input
	if Input.is_action_just_pressed(&"grapple") and can_grapple:
		attempt_grapple()

	# Release grapple on button release
	if Input.is_action_just_released(&"grapple") and is_grappling:
		end_grapple()

	# Apply grapple physics if active
	if is_grappling:
		apply_grapple_physics(delta)
		
		# Update grapple rope visual
		update_grapple_rope()

# Try to start a grapple
func attempt_grapple() -> void:
	if grapple_raycast.is_colliding():
		# Get the collision point and normal
		var collider = grapple_raycast.get_collider()
		
		# Check if we hit an enemy
		if collider.is_in_group("enemies") and collider.has_method("get_grapple_point"):
			# Use the enemy's grapple point
			grapple_point = collider.get_grapple_point()
			grapple_normal = (grapple_point - global_position).normalized()
			grapple_object = collider
			start_grapple()
		# Otherwise, use the standard grapple logic for environment
		elif collider is StaticBody3D or "grappleable" in collider.get_groups():
			grapple_point = grapple_raycast.get_collision_point()
			grapple_normal = grapple_raycast.get_collision_normal()
			grapple_object = collider
			start_grapple()
		else:
			# Visual feedback for non-grappleable object
			print("Cannot grapple to this surface")

# Start the grapple
func start_grapple() -> void:
	is_grappling = true
	can_grapple = false
	grapple_cooldown_timer = 0.0
	
	# Calculate initial rope length
	grapple_length = global_position.distance_to(grapple_point)
	
	# Show all rope segments
	for segment in rope_segment_meshes:
		if is_instance_valid(segment):
			segment.visible = true
	
	# Show the hook
	if hook_mesh:
		hook_mesh.visible = true
	
	# Add a slight upward boost when starting grapple
	if !is_on_floor():
		velocity.y += 5.0
	
	# Tell the head we're grappling
	if head and head.has_method("set_grappling"):
		head.set_grappling(true)

# End the grapple
func end_grapple() -> void:
	is_grappling = false
	
	# Hide all rope segments
	for segment in rope_segment_meshes:
		if is_instance_valid(segment):
			segment.visible = false
	
	# Hide the hook
	if hook_mesh:
		hook_mesh.visible = false
	
	# Preserve some momentum when releasing
	var forward_dir = -head.global_transform.basis.z.normalized()
	velocity += forward_dir * 10.0
	
	# Tell the head we're no longer grappling
	if head and head.has_method("set_grappling"):
		head.set_grappling(false)
	
	# Start cooldown
	grapple_cooldown_timer = 0.0

# Apply physics while grappling
func apply_grapple_physics(delta: float) -> void:
	# Get direction to grapple point
	var to_grapple = grapple_point - global_position
	var distance = to_grapple.length()
	var grapple_dir = to_grapple.normalized()
	
	# Get player's input direction for swinging influence
	var input_dir = Vector3(input_axis.y, 0, -input_axis.x).normalized()
	var right_vector = head.global_transform.basis.x
	var swing_force = right_vector * input_dir.x * grapple_swing_influence
	
	# Apply pull force toward grapple point
	var pull_strength = grapple_pull_speed
	
	# Adjust pull strength based on angle (stronger when looking at target)
	var look_dot = grapple_dir.dot(-head.global_transform.basis.z)
	pull_strength *= clamp(look_dot * 1.5, 0.5, 1.5)
	
	# Calculate final grapple velocity
	var grapple_velocity = grapple_dir * pull_strength
	
	# Add swing influence
	grapple_velocity += swing_force
	
	# Blend between current velocity and grapple velocity
	velocity = velocity.lerp(grapple_velocity, delta * 5.0)
	
	# Allow jumping to cancel grapple with a boost
	if Input.is_action_just_pressed(&"jump"):
		velocity.y = jump_height * 1.1
		end_grapple()

# Update the rope visual
func update_grapple_rope() -> void:
	if !is_grappling or rope_segment_meshes.size() == 0:
		return
	
	# Get the camera position as the start point
	var start_pos = $Head/Camera.global_position
	
	# Calculate points along the rope with a slight curve
	var points = []
	for i in range(rope_segments + 1):
		var t = float(i) / rope_segments
		var point = start_pos.lerp(grapple_point, t)
		
		# Add a slight curve to the rope
		if t > 0 and t < 1:
			# Calculate perpendicular vector for curve
			var dir = (grapple_point - start_pos).normalized()
			var up = Vector3.UP
			if dir.dot(up) > 0.9:  # If rope is mostly vertical
				up = Vector3.RIGHT  # Use a different perpendicular vector
			
			var perp = dir.cross(up).normalized()
			
			# Add curve based on sine wave
			var curve_amount = sin(t * PI) * 0.3  # Max curve at middle
			
			# Apply curve and some randomness for rope physics feel
			point += perp * curve_amount
			point.y -= sin(t * PI) * 0.2  # Slight downward curve from gravity
			
			# Add subtle movement to make rope feel alive
			var time_offset = Time.get_ticks_msec() * 0.001
			point += perp * sin(time_offset * 3.0 + t * 10.0) * 0.05
			point += up * cos(time_offset * 2.0 + t * 8.0) * 0.05
		
		points.append(point)
	
	# Update each segment
	for i in range(rope_segments):
		var segment = rope_segment_meshes[i]
		if !is_instance_valid(segment):
			continue
			
		var start = points[i]
		var end = points[i + 1]
		
		# Position at midpoint
		var mid_point = (start + end) / 2.0
		segment.global_position = mid_point
		
		# Calculate length
		var segment_length = start.distance_to(end)
		segment.scale.y = segment_length
		
		# Rotate to point at end
		segment.look_at(end, Vector3.UP)
		segment.rotate_object_local(Vector3(1, 0, 0), PI/2)
		
		# Make visible
		segment.visible = true
	
	# Update the hook position and rotation
	if hook_mesh:
		hook_mesh.global_position = grapple_point
		hook_mesh.look_at(points[rope_segments - 1], Vector3.UP)
		hook_mesh.rotate_object_local(Vector3(1, 0, 0), -PI/2)
		hook_mesh.visible = true
		
		# Add subtle rotation to hook for visual interest
		hook_mesh.rotate_object_local(Vector3(0, 0, 1), sin(Time.get_ticks_msec() * 0.01) * 0.1)

# Add this function to handle taking damage
func take_damage(amount: float) -> void:
	current_health = clamp(current_health - amount, 0, max_health)
	
	# You could add effects here like screen shake, flash, etc.
	if current_health <= 0:
		die()

# Add this function to handle healing
func heal(amount: float) -> void:
	current_health = clamp(current_health + amount, 0, max_health)

# Add this function to handle death
func die() -> void:
	# Handle player death
	# This could reset the level, show game over screen, etc.
	print("Player died!")
	
	# For testing, just reset health
	current_health = max_health

func _on_jumppad_contact(jump_force: float, forward_force: float = 0.0):
	# Apply vertical force
	velocity.y = jump_force
	
	# Apply forward force if specified
	if forward_force > 0:
		var forward_dir = -transform.basis.z.normalized()
		velocity.x += forward_dir.x * forward_force
		velocity.z += forward_dir.z * forward_force
	
	# Add camera shake if available
	if head and head.has_method("add_camera_shake"):
		head.add_camera_shake(0.3, 0.2)
