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

# Ground pound parameters
@export var ground_pound_speed := 150.0  # Downward velocity during ground pound
@export var ground_pound_impact_radius := 50.0  # Radius of impact effect
@export var ground_pound_impact_force := 150.0  # Force applied to nearby objects
@export var ground_pound_cooldown := 0.5  # Cooldown after ground pound
var is_ground_pounding := false  # Whether the player is currently ground pounding
var ground_pound_cooldown_timer := 0.0  # Cooldown timer
var ground_pound_start_height := 0.0  # Height from which the ground pound started
var can_ground_pound := true  # Whether the player can ground pound

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

#Damage
@export var damage_cooldown := 0.5  # Time between taking damage
var damage_timer := 0.0  # Timer for damage cooldown
var is_invulnerable := false  # Invulnerability after taking damage

# Grapple rope visual
var rope_segments := 12  # Increased number of rope segments
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
	
	# Make sure hitbox is in player_weapon group
	if hitbox:
		hitbox.add_to_group("player_weapon")
		print("Added hitbox to player_weapon group in _ready")


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("attack"):
		print("Attack pressed")
		anim_player.play("attack")
		
		# Make sure hitbox is in player_weapon group
		if hitbox:
			hitbox.add_to_group("player_weapon")
			print("Added hitbox to player_weapon group: ", hitbox.get_groups())
			
		# Enable monitoring
		if hitbox:
			hitbox.monitoring = true


# Called every physics tick. 'delta' is constant
func _physics_process(delta: float) -> void:
	input_axis = Input.get_vector(&"move_back", &"move_forward",
			&"move_left", &"move_right")
			
	# Update damage cooldown timer
	if damage_timer > 0:
		damage_timer -= delta
		if damage_timer <= 0:
			is_invulnerable = false

	direction_input()

	# Track previous states for bunny hop logic
	was_dashing = is_dashing
	was_sliding = is_sliding

	# Update ground pound cooldown
	if !can_ground_pound:
		ground_pound_cooldown_timer += delta
		if ground_pound_cooldown_timer >= ground_pound_cooldown:
			can_ground_pound = true
			ground_pound_cooldown_timer = 0.0

	# Check for ground pound input (same as slide key, but in air)
	if !is_on_floor() and Input.is_action_just_pressed(&"slide") and !is_dashing and !is_sliding and !is_grappling and !is_ground_pounding and can_ground_pound:
		start_ground_pound()

	# Handle ground pound physics
	if is_ground_pounding:
		# Apply downward velocity
		velocity.y = -ground_pound_speed
		
		# Check for ground impact
		if is_on_floor():
			ground_pound_impact()

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

	# Only apply normal movement if not in a special movement state
	if !is_dashing and !is_sliding and !is_grappling and !is_ground_pounding:
		if is_on_floor():
			if Input.is_action_just_pressed(&"jump"):
				handle_jump()
		else:
			velocity.y -= gravity * delta
		
		accelerate(delta)
	elif is_ground_pounding:
		# Ground pound physics handled in the ground pound section
		# Just apply horizontal deceleration
		velocity.x = lerp(velocity.x, 0.0, delta * 2.0)
		velocity.z = lerp(velocity.z, 0.0, delta * 2.0)
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
			# No gravity during dash, but preserve upward velocity from jumppads
			if velocity.y > 0:
				# Keep some of the upward velocity
				velocity.y = velocity.y * 0.9
			else:
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

func _on_jumppad_contact(jump_force: float, forward_force: float = 0.0, override_states: bool = true):
	print("Jumppad contact received with force: ", jump_force)
	
	# If we should override movement states or we're not in a special movement state
	if override_states or (!is_dashing and !is_sliding and !is_grappling):
		# Apply vertical force
		velocity.y = jump_force
		
		# Apply forward force if specified
		if forward_force > 0:
			var forward_dir = -transform.basis.z.normalized()
			velocity.x += forward_dir.x * forward_force
			velocity.z += forward_dir.z * forward_force
		
		# If we're dashing or sliding, end those states
		if is_dashing and override_states:
			print("Ending dash due to jumppad")
			is_dashing = false
			dash_timer = 0.0
		
		if is_sliding and override_states:
			print("Ending slide due to jumppad")
			end_slide()
		
		# Add camera shake if available
		if head and head.has_method("add_camera_shake"):
			head.add_camera_shake(0.3, 0.2)
		
		print("Applied jumppad forces. New velocity: ", velocity)
	else:
		print("Jumppad ignored due to movement state: dashing=", is_dashing, ", sliding=", is_sliding, ", grappling=", is_grappling)

# SLIDE MECHANIC
func handle_slide(delta: float) -> void:
	# Start sliding - ULTRAKILL style (only when on ground)
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
		else:
			# If we're in the air during a slide (like from a jumppad),
			# apply gravity but at a reduced rate to maintain height longer
			velocity.y -= gravity * delta * 0.7
		
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

# Start a ground pound
func start_ground_pound() -> void:
	is_ground_pounding = true
	can_ground_pound = false
	ground_pound_cooldown_timer = 0.0
	ground_pound_start_height = global_position.y
	
	# Store current horizontal velocity to preserve some momentum
	var horizontal_velocity = Vector3(velocity.x, 0, velocity.z)
	
	# Apply immediate downward velocity
	velocity.y = -ground_pound_speed
	
	# Reduce horizontal velocity but maintain some direction
	velocity.x *= 0.5
	velocity.z *= 0.5
	
	# Tell the head to add camera effects
	if head and head.has_method("add_camera_shake"):
		head.add_camera_shake(0.2, 0.2)
	
	# Tell the head we're ground pounding
	if head and head.has_method("set_ground_pounding"):
		head.set_ground_pounding(true)
	
	print("Started ground pound from height: ", ground_pound_start_height)

# Handle ground pound impact
func ground_pound_impact() -> void:
	is_ground_pounding = false
	
	# Calculate impact force based on height fallen
	var height_fallen = ground_pound_start_height - global_position.y
	var impact_force = clamp(height_fallen * 0.5, 5.0, ground_pound_impact_force)
	
	print("Ground pound impact with force: ", impact_force)
	
	# Add camera shake on impact
	if head and head.has_method("add_camera_shake"):
		head.add_camera_shake(0.4, 0.3)
	
	# Tell the head we're no longer ground pounding
	if head and head.has_method("set_ground_pounding"):
		head.set_ground_pounding(false)
	
	# Apply impact force to nearby objects
	apply_ground_pound_force(impact_force)
	
	# Create visual effect
	create_ground_pound_effect()

# Apply force to nearby objects
func apply_ground_pound_force(impact_force: float) -> void:
	# Get all bodies in the impact radius
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsShapeQueryParameters3D.new()
	
	# Create a sphere shape for the query
	var shape = SphereShape3D.new()
	shape.radius = ground_pound_impact_radius
	query.shape = shape
	query.transform = Transform3D(Basis(), global_position)
	
	# Exclude the player from the query
	query.exclude = [self]
	
	# Query for overlapping bodies
	var results = space_state.intersect_shape(query)
	
	# Apply force to each body
	for result in results:
		var body = result["collider"]
		
		# Check if it's a physics body
		if body is RigidBody3D:
			# Calculate direction from player to body
			var direction = (body.global_position - global_position).normalized()
			direction.y = abs(direction.y) + 0.5  # Add upward component
			
			# Calculate force based on distance
			var distance = global_position.distance_to(body.global_position)
			var force_multiplier = 1.0 - clamp(distance / ground_pound_impact_radius, 0.0, 1.0)
			var force = direction * impact_force * force_multiplier * body.mass
			
			# Apply the impulse
			body.apply_impulse(force, body.global_position)
			
			print("Applied force to ", body.name, ": ", force)
		
		# Check if it's an enemy
		elif body.is_in_group("enemies") and body.has_method("take_damage"):
			# Calculate damage based on distance
			var distance = global_position.distance_to(body.global_position)
			var damage_multiplier = 1.0 - clamp(distance / ground_pound_impact_radius, 0.0, 1.0)
			var damage = impact_force * damage_multiplier
			
			# Apply damage
			body.take_damage(damage)
			
			print("Applied damage to ", body.name, ": ", damage)

# Create visual effect for ground pound
func create_ground_pound_effect() -> void:
	# Create a ring effect at the impact point
	var ring_effect = CPUParticles3D.new()
	add_child(ring_effect)
	
	# Position slightly above ground to avoid clipping
	ring_effect.position = Vector3(0, 0.1, 0)
	
	# Set up particle properties
	ring_effect.emitting = true
	ring_effect.one_shot = true
	ring_effect.explosiveness = 0.9
	ring_effect.amount = 24
	ring_effect.lifetime = 0.5
	
	# Set emission shape to ring
	ring_effect.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	ring_effect.emission_ring_radius = 0.1
	ring_effect.emission_ring_height = 0.0
	ring_effect.emission_ring_axis = Vector3(0, 1, 0)
	
	# Set particle direction and spread
	ring_effect.direction = Vector3(0, 0.1, 0)
	ring_effect.spread = 180.0
	
	# Set particle velocity
	ring_effect.initial_velocity_min = 5.0
	ring_effect.initial_velocity_max = 10.0
	
	# Set particle size
	ring_effect.scale_amount_min = 0.2
	ring_effect.scale_amount_max = 0.5
	
	# Set particle color
	ring_effect.color = Color(1.0, 0.5, 0.0)  # Orange to match grapple
	
	# Auto-remove after particles are done
	var timer = Timer.new()
	add_child(timer)
	timer.wait_time = 1.0
	timer.one_shot = true
	timer.timeout.connect(func(): ring_effect.queue_free(); timer.queue_free())
	timer.start()

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
	
	# Create enhanced material for the rope with bright orange color and high visibility
	rope_material = StandardMaterial3D.new()
	rope_material.albedo_color = Color(1.0, 0.5, 0.0)  # Bright orange
	rope_material.metallic = 1.0  # Maximum metallic for shininess
	rope_material.roughness = 0.1  # Low roughness for more shine
	
	# Strong emission for better visibility
	rope_material.emission_enabled = true
	rope_material.emission = Color(1.0, 0.5, 0.0)  # Match the orange color
	rope_material.emission_energy = 3.0  # Higher emission energy for glow
	
	# Create segments
	for i in range(rope_segments):
		var segment = MeshInstance3D.new()
		segment.name = "RopeSegment" + str(i)
		add_child(segment)
		
		# Create a slightly thicker cylinder for better visibility
		var cylinder = CylinderMesh.new()
		cylinder.top_radius = 0.025  # Slightly thicker
		cylinder.bottom_radius = 0.025
		cylinder.height = 1.0  # Will be scaled dynamically
		cylinder.radial_segments = 8
		
		segment.mesh = cylinder
		segment.material_override = rope_material
		segment.visible = false  # Will be made visible when grappling
		
		rope_segment_meshes.append(segment)
	
	# Create a hook at the end with enhanced glow
	hook_mesh = MeshInstance3D.new()
	hook_mesh.name = "GrappleHook"
	add_child(hook_mesh)
	
	# Create a simple cone for the hook
	var cone = CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.08  # Slightly larger for visibility
	cone.height = 0.2
	
	# Create a separate material for the hook with stronger glow
	var hook_material = StandardMaterial3D.new()
	hook_material.albedo_color = Color(1.0, 0.5, 0.0)  # Bright orange
	hook_material.metallic = 1.0
	hook_material.roughness = 0.1
	
	# Stronger emission for the hook
	hook_material.emission_enabled = true
	hook_material.emission = Color(1.0, 0.6, 0.2)  # Slightly brighter
	hook_material.emission_energy = 4.0  # Even stronger emission
	
	hook_mesh.mesh = cone
	hook_mesh.material_override = hook_material
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
	print("Attempting to grapple")
	
	if grapple_raycast.is_colliding():
		# Get the collision point and normal
		var collider = grapple_raycast.get_collider()
		var collision_point = grapple_raycast.get_collision_point()
		
		print("Raycast hit: ", collider.name, " at position: ", collision_point)
		
		# Check if we hit an enemy
		if collider.is_in_group("enemies") and collider.has_method("get_grapple_point"):
			# Use the enemy's grapple point
			grapple_point = collider.get_grapple_point()
			grapple_normal = (grapple_point - global_position).normalized()
			grapple_object = collider
			start_grapple()
		# Otherwise, use the standard grapple logic for environment
		elif collider is StaticBody3D or "grappleable" in collider.get_groups():
			grapple_point = collision_point
			grapple_normal = grapple_raycast.get_collision_normal()
			grapple_object = collider
			start_grapple()
		else:
			# Visual feedback for non-grappleable object
			print("Cannot grapple to this surface: ", collider.name)
	else:
		print("Grapple raycast did not hit anything")

# Start the grapple
func start_grapple() -> void:
	is_grappling = true
	can_grapple = false
	grapple_cooldown_timer = 0.0
	
	# Calculate initial rope length
	grapple_length = global_position.distance_to(grapple_point)
	
	# Show all rope segments - make sure they're visible
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
	
	# Debug print to confirm grapple started
	print("Grapple started - rope segments: ", rope_segment_meshes.size())

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
	
	# Debug print (only occasionally to avoid spam)
	if Engine.get_frames_drawn() % 60 == 0:  # Print once per second at 60 FPS
		print("Updating rope with ", rope_segment_meshes.size(), " segments")
	
	# Get the camera position as the start point
	var start_pos = $Head/Camera.global_position
	
	# Calculate points along the rope with a more dynamic curve
	var points = []
	for i in range(rope_segments + 1):
		var t = float(i) / rope_segments
		var point = start_pos.lerp(grapple_point, t)
		
		# Add a more pronounced curve to the rope
		if t > 0 and t < 1:
			# Calculate perpendicular vector for curve
			var dir = (grapple_point - start_pos).normalized()
			var up = Vector3.UP
			if dir.dot(up) > 0.9:  # If rope is mostly vertical
				up = Vector3.RIGHT  # Use a different perpendicular vector
			
			var perp = dir.cross(up).normalized()
			
			# Add curve based on sine wave
			var curve_amount = sin(t * PI) * 0.4
			
			# Apply curve and some randomness for rope physics feel
			point += perp * curve_amount
			point.y -= sin(t * PI) * 0.25
			
			# Add more pronounced movement to make rope feel alive
			var time_offset = Time.get_ticks_msec() * 0.001
			point += perp * sin(time_offset * 4.0 + t * 12.0) * 0.08
			point += up * cos(time_offset * 3.0 + t * 10.0) * 0.08
		
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
		
		# Make sure it's visible
		segment.visible = true
	
	# Update the hook position and rotation
	if hook_mesh:
		hook_mesh.global_position = grapple_point
		hook_mesh.look_at(points[rope_segments - 1], Vector3.UP)
		hook_mesh.rotate_object_local(Vector3(1, 0, 0), -PI/2)
		hook_mesh.visible = true
		
		# Add subtle rotation to hook for visual interest
		hook_mesh.rotate_object_local(Vector3(0, 0, 1), sin(Time.get_ticks_msec() * 0.01) * 0.2)

# Add this function to handle healing
func heal(amount: float) -> void:
	current_health = clamp(current_health + amount, 0, max_health)

# Function to take damage from enemies
func take_damage(amount: float) -> void:
	# Skip if invulnerable
	if is_invulnerable:
		print("Player is invulnerable, ignoring damage")
		return
		
	print("Player taking damage: ", amount)
	current_health -= amount
	
	# Make player briefly invulnerable
	is_invulnerable = true
	damage_timer = damage_cooldown
	
	# Visual feedback for taking damage
	if head and head.has_method("add_camera_shake"):
		head.add_camera_shake(0.3, 0.2)
	
	# Print current health for debugging
	print("Player health: ", current_health, "/", max_health)
	
	# Check for death
	if current_health <= 0:
		die()

# Function for player death
func die() -> void:
	print("Player died!")
	
	# For testing, just reset health
	current_health = max_health
	
	# You could add more death logic here, like respawning
	# or showing a game over screen

func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "attack":
		anim_player.play("idle")
		if hitbox:
			hitbox.monitoring = false

func _on_hitbox_area_entered(area: Area3D) -> void:
	if area.is_in_group("enemy"):
		print("enemy hit")
