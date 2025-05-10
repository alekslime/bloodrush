extends CharacterBody3D
class_name MovementController

# Basic movement parameters
@export var gravity_multiplier := 3.0
@export var speed := 25
@export var acceleration := 15
@export var deceleration := 15
@export_range(0.0, 1.0, 0.05) var air_control := 0.6
@export var jump_height := 15

# Dash parameters - Now with limited dashes
@export var dash_speed := 130.0
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
@export var slide_boost := 4.0
@export var slide_friction := 0.05
var is_sliding := false
var slide_timer := 0.0
var slide_direction := Vector3.ZERO
var was_sliding := false  # Track if player was just sliding (for bunny hop control)

# Bunny hop parameters
@export var bhop_boost := 1.2  # Boost factor for slide bunny hops
var bhop_window := 0.2  # Time window to perform a bunny hop after slide
var bhop_timer := 0.0  # Timer for bunny hop window

# Grapple parameters
@export var grapple_max_distance := 100.0
@export var grapple_pull_speed := 40.0
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
var rope_mesh: MeshInstance3D
var rope_material: StandardMaterial3D

# Reference to head node for camera control
@onready var head: Node3D = $Head  # Make sure this path matches your scene structure

# Reference to raycast for grapple detection
@onready var grapple_raycast: RayCast3D = $Head/Camera/GrappleRaycast

# Reference to gun
@onready var gun: Gun = $Head/Camera/Gun if has_node("Head/Camera/Gun") else null

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
	
	# Fix the indentation in this block
	if !gun:
		if ResourceLoader.exists("res://gun.tscn"):
			var gun_scene = load("res://gun.tscn")
			gun = gun_scene.instantiate()
			$Head/Camera.add_child(gun)
			gun.position = Vector3(0.5, -0.3, -0.7)  # Position the gun in view
		else:
		# Create a simple placeholder gun if the scene doesn't exist
			gun = Gun.new()
			$Head/Camera.add_child(gun)
			gun.position = Vector3(0.5, -0.3, -0.7)

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
	
	# Update grapple rope visual
	if is_grappling:
		update_grapple_rope()
	
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
	rope_mesh = MeshInstance3D.new()
	add_child(rope_mesh)
	
	# Create a simple cylinder mesh for the rope
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 0.03
	cylinder.bottom_radius = 0.03
	cylinder.height = 1.0  # Will be scaled dynamically
	
	rope_mesh.mesh = cylinder
	
	# Create material for the rope
	rope_material = StandardMaterial3D.new()
	rope_material.albedo_color = Color(0.8, 0.8, 0.8)
	rope_material.roughness = 0.7
	
	rope_mesh.material_override = rope_material
	rope_mesh.visible = false

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

# Try to start a grapple
func attempt_grapple() -> void:
	if grapple_raycast.is_colliding():
		# Get the collision point and normal
		grapple_point = grapple_raycast.get_collision_point()
		grapple_normal = grapple_raycast.get_collision_normal()
		grapple_object = grapple_raycast.get_collider()
		
		# Check if the object is grappleable (you can add a tag or group check here)
		# For now, we'll assume all static objects are grappleable
		if grapple_object is StaticBody3D or "grappleable" in grapple_object.get_groups():
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
	
	# Show the rope
	rope_mesh.visible = true
	
	# Add a slight upward boost when starting grapple
	if !is_on_floor():
		velocity.y += 5.0
	
	# Tell the head we're grappling
	if head and head.has_method("set_grappling"):
		head.set_grappling(true)
	
	# Play sound effect
	# if has_node("GrappleSound"):
	#     $GrappleSound.play()

# End the grapple
func end_grapple() -> void:
	is_grappling = false
	rope_mesh.visible = false
	
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
	if !is_grappling or !rope_mesh:
		return
	
	# Get the camera position as the start point
	var start_pos = $Head/Camera.global_position
	
	# Calculate the midpoint between the player and grapple point
	var mid_point = (start_pos + grapple_point) / 2.0
	
	# Set the rope position to the midpoint
	rope_mesh.global_position = mid_point
	
	# Calculate the distance and direction
	var to_grapple = grapple_point - start_pos
	var distance = to_grapple.length()
	
	# Scale the rope to match the distance
	rope_mesh.scale.y = distance
	
	# Rotate the rope to point at the grapple point
	# We need to look_at the grapple point, but the cylinder's axis is Y
	rope_mesh.look_at(grapple_point, Vector3.UP)
	rope_mesh.rotate_object_local(Vector3(1, 0, 0), PI/2)
