extends CharacterBody3D

# Enemy properties
@export var move_speed := 3.0
@export var damage := 20.0
@export var attack_cooldown := 1.0
@export var max_health := 100.0
@export var attack_range := 2.0
@export var detection_range := 20.0
@export var stagger_threshold := 50.0

var current_health := 100.0
var stagger_amount := 0.0
var is_dead := false
var attack_timer := 0.0
var attack_area: Area3D

# State machine
enum State {IDLE, CHASE, ATTACK, STAGGER, DEAD}
var current_state = State.IDLE

# References
@onready var mesh_instance = $MeshInstance3D if has_node("MeshInstance3D") else null
@onready var animation_player = $AnimationPlayer if has_node("AnimationPlayer") else null
@onready var state_timer := 0.0
@onready var debug_label = $DebugLabel if has_node("DebugLabel") else null

# Navigation
@onready var nav_agent = $NavigationAgent3D if has_node("NavigationAgent3D") else null
var path_update_timer := 0.0
var path_update_interval := 0.5

# Target
var player = null

func _ready():
	# Initialize health
	current_health = max_health
	
	# Find player
	find_player()
	
	# Add to enemy group
	add_to_group("enemy")
	
	# Setup navigation if agent exists
	if nav_agent:
		nav_agent.max_speed = move_speed
	
	# Setup hit area
	setup_hit_area()
	
	# Setup attack area
	setup_attack_area()
	
	# Add debug label if it doesn't exist
	if !debug_label:
		debug_label = Label3D.new()
		debug_label.name = "DebugLabel"
		add_child(debug_label)
		debug_label.position = Vector3(0, 2.5, 0)
		debug_label.billboard = true
		debug_label.font_size = 16
		debug_label.modulate = Color(1, 0, 0)  # Red
	
	update_debug_label()
	print("Enemy initialized with health: ", current_health)

func setup_hit_area():
	# Check for existing hit area
	var hit_area = get_node_or_null("HitArea")
	
	# Create new hit area if needed
	if !hit_area:
		hit_area = Area3D.new()
		hit_area.name = "HitArea"
		add_child(hit_area)
		
		# Create collision shape
		var shape = BoxShape3D.new()
		shape.size = Vector3(2.0, 3.0, 2.0)  # Large for easier detection
		var collision = CollisionShape3D.new()
		collision.shape = shape
		hit_area.add_child(collision)
		
		print("Created new HitArea")
	else:
		print("Using existing HitArea")
	
	# Add to enemy group
	hit_area.add_to_group("enemy")
	
	# Connect signal if not already connected
	if !hit_area.is_connected("area_entered", _on_hit_area_area_entered):
		hit_area.connect("area_entered", _on_hit_area_area_entered)
		print("Connected area_entered signal")
	
	print("HitArea setup complete")

func setup_attack_area():
	# Create a dedicated area for attacking the player
	attack_area = Area3D.new()
	attack_area.name = "AttackArea"
	add_child(attack_area)
	
	# Create a slightly larger collision shape for attack detection
	var shape = SphereShape3D.new()
	shape.radius = attack_range * 0.75  # Adjust based on attack range
	var collision = CollisionShape3D.new()
	collision.shape = shape
	attack_area.add_child(collision)
	
	# Set collision mask to detect player
	attack_area.collision_mask = 1  # Adjust to match player's layer
	
	# Connect body entered signal
	attack_area.connect("body_entered", _on_attack_area_body_entered)
	
	print("Attack area setup complete")

func _physics_process(delta):
	# Skip if dead
	if current_state == State.DEAD:
		return
	
	# Update timers
	attack_timer -= delta if attack_timer > 0 else 0
	state_timer -= delta if state_timer > 0 else 0
	path_update_timer -= delta if path_update_timer > 0 else 0
	
	# Reduce stagger over time
	if stagger_amount > 0:
		stagger_amount -= delta * 10.0
	
	# Skip if no player
	if !player:
		find_player()
		return
	
	# Update state machine
	match current_state:
		State.IDLE:
			process_idle_state(delta)
		State.CHASE:
			process_chase_state(delta)
		State.ATTACK:
			process_attack_state(delta)
		State.STAGGER:
			process_stagger_state(delta)
	
	# Update debug label
	update_debug_label()
	
	# Move
	move_and_slide()

func process_idle_state(delta):
	# Check if player is in detection range
	var distance_to_player = global_position.distance_to(player.global_position)
	
	if distance_to_player < detection_range:
		change_state(State.CHASE)
		return
	
	# Idle behavior - slight random movement
	if state_timer <= 0:
		# Random idle duration
		state_timer = randf_range(1.0, 3.0)
		
		# Random movement
		var random_dir = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		velocity = random_dir * move_speed * 0.3
	else:
		# Slow down over time
		velocity = velocity.lerp(Vector3.ZERO, delta * 2.0)

func process_chase_state(delta):
	# Check if player is in attack range
	var distance_to_player = global_position.distance_to(player.global_position)
	
	if distance_to_player < attack_range and attack_timer <= 0:
		change_state(State.ATTACK)
		return
	
	# Update navigation path
	if path_update_timer <= 0:
		update_navigation_path()
		path_update_timer = path_update_interval
	
	# Follow navigation path
	if nav_agent and nav_agent.is_navigation_finished() == false:
		var next_position = nav_agent.get_next_path_position()
		var direction = (next_position - global_position).normalized()
		direction.y = 0  # Keep on XZ plane
		
		# Set velocity
		velocity = direction * move_speed
		
		# Rotate toward movement direction
		look_at(Vector3(next_position.x, global_position.y, next_position.z), Vector3.UP)
	else:
		# Direct movement if no navigation
		var direction = (player.global_position - global_position).normalized()
		direction.y = 0  # Keep on XZ plane
		
		# Set velocity
		velocity = direction * move_speed
		
		# Rotate toward player
		look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z), Vector3.UP)

func process_attack_state(delta):
	# Stop movement during attack
	velocity = Vector3.ZERO
	
	# Face player
	look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z), Vector3.UP)
	
	# Perform attack
	if state_timer <= 0:
		perform_attack()
		
		# Set cooldown
		attack_timer = attack_cooldown
		
		# Return to chase state
		change_state(State.CHASE)

func process_stagger_state(delta):
	# Apply stagger movement - slight backward movement
	var direction = (global_position - player.global_position).normalized()
	direction.y = 0
	velocity = direction * move_speed * 0.5
	
	# Return to chase after stagger
	if state_timer <= 0:
		change_state(State.CHASE)

func change_state(new_state):
	current_state = new_state
	
	match new_state:
		State.IDLE:
			print("Enemy state: IDLE")
			state_timer = randf_range(1.0, 3.0)
		State.CHASE:
			print("Enemy state: CHASE")
			# Update path immediately
			update_navigation_path()
		State.ATTACK:
			print("Enemy state: ATTACK")
			state_timer = 0.5  # Wind-up time before attack
		State.STAGGER:
			print("Enemy state: STAGGER")
			state_timer = 0.5  # Stagger duration
		State.DEAD:
			print("Enemy state: DEAD")
			die()

func update_navigation_path():
	if nav_agent and player:
		nav_agent.target_position = player.global_position

func perform_attack():
	print("Enemy attacking player!")
	
	# Play attack animation if available
	if animation_player and animation_player.has_animation("attack"):
		animation_player.play("attack")
	
	# Check if player is still in range
	var distance_to_player = global_position.distance_to(player.global_position)
	
	if distance_to_player < attack_range * 1.2:  # Slightly larger range for attack
		# Apply damage to player
		if player.has_method("take_damage"):
			player.take_damage(damage)
			print("Dealt ", damage, " damage to player")
			
			# Visual feedback for attack
			if mesh_instance:
				var attack_material = StandardMaterial3D.new()
				attack_material.albedo_color = Color(1, 0.5, 0)  # Orange for attack
				attack_material.emission_enabled = true
				attack_material.emission = Color(1, 0.5, 0)
				attack_material.emission_energy = 1.0
				
				var original_material = mesh_instance.get_surface_override_material(0)
				mesh_instance.set_surface_override_material(0, attack_material)
				
				# Reset material after a short time
				var timer = get_tree().create_timer(0.2)
				timer.timeout.connect(func(): 
					if is_instance_valid(mesh_instance):
						mesh_instance.set_surface_override_material(0, original_material)
				)
		else:
			print("WARNING: Player doesn't have take_damage method!")
	else:
		print("Player moved out of attack range")

func find_player():
	# Try to find player by group
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]
		print("Found player by group: ", player.name)
		return
	
	# Try to find by class as fallback
	var nodes = get_tree().get_nodes_in_group("MovementController")
	for node in nodes:
		if node.get_script() and node.get_script().resource_path.find("MovementController") >= 0:
			player = node
			print("Found player by script: ", player.name)
			player.add_to_group("player")
			return
	
	print("WARNING: No player found!")

func _on_hit_area_area_entered(area):
	# Skip if dead
	if current_state == State.DEAD:
		return
	
	# Safety check for null
	if area == null:
		print("WARNING: Null area entered hit area")
		return
	
	print("Area entered hit area: ", area.name)
	
	# Manually add the area to player_weapon group if it's named Hitbox
	if area.name == "Hitbox":
		area.add_to_group("player_weapon")
		print("Manually added Hitbox to player_weapon group")
	
	# Print all groups for debugging
	print("Area groups after potential addition: ", area.get_groups())
	
	# Check if it's a player weapon
	if area.is_in_group("player_weapon"):
		print("Hit by player weapon!")
		take_damage(25.0)
	else:
		print("Area is not a player weapon. Groups: ", area.get_groups())

func _on_attack_area_body_entered(body):
	# Skip if dead or on cooldown
	if current_state == State.DEAD or attack_timer > 0:
		return
	
	# Check if it's the player
	if body == player:
		print("Player entered attack area!")
		# Use our state-based attack system
		if current_state != State.ATTACK:
			change_state(State.ATTACK)

func take_damage(amount):
	# Skip if dead
	if current_state == State.DEAD:
		return
	
	print("Enemy taking damage: ", amount)
	current_health -= amount
	
	# Increase stagger amount
	stagger_amount += amount
	
	# Check for stagger threshold
	if stagger_amount > stagger_threshold and current_state != State.STAGGER:
		change_state(State.STAGGER)
		stagger_amount = 0.0
	
	# Update debug label
	update_debug_label()
	
	# Flash red when hit
	if mesh_instance:
		var original_material = mesh_instance.get_surface_override_material(0)
		var hit_material = StandardMaterial3D.new()
		hit_material.albedo_color = Color(1, 0, 0)  # Red
		hit_material.emission_enabled = true
		hit_material.emission = Color(1, 0, 0)
		hit_material.emission_energy = 2.0
		
		mesh_instance.set_surface_override_material(0, hit_material)
		
		# Reset material after a short time
		var timer = get_tree().create_timer(0.2)
		timer.timeout.connect(func(): 
			if is_instance_valid(mesh_instance):
				mesh_instance.set_surface_override_material(0, original_material)
		)
	
	# Check for death
	if current_health <= 0:
		change_state(State.DEAD)

func update_debug_label():
	if debug_label:
		var state_text = ""
		match current_state:
			State.IDLE: state_text = "IDLE"
			State.CHASE: state_text = "CHASE"
			State.ATTACK: state_text = "ATTACK"
			State.STAGGER: state_text = "STAGGER"
			State.DEAD: state_text = "DEAD"
		
		debug_label.text = "HP: " + str(int(current_health)) + "\nState: " + state_text

func die():
	print("Enemy died!")
	is_dead = true
	
	# Play death animation if available
	if animation_player and animation_player.has_animation("death"):
		animation_player.play("death")
	
	# Play death effect
	if mesh_instance:
		# Create a tween for fading out
		var tween = create_tween()
		tween.tween_property(mesh_instance, "scale", Vector3(1.5, 0.01, 1.5), 0.5)
		
		# Create particles for death effect
		var particles = GPUParticles3D.new()
		add_child(particles)
		
		# Set up particle material
		var particle_material = ParticleProcessMaterial.new()
		particle_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		particle_material.emission_sphere_radius = 1.0
		particle_material.direction = Vector3(0, 1, 0)
		particle_material.spread = 180.0
		particle_material.initial_velocity_min = 2.0
		particle_material.initial_velocity_max = 5.0
		particle_material.gravity = Vector3(0, -9.8, 0)
		particle_material.color = Color(1, 0.3, 0.1)  # Orange-red
		
		particles.process_material = particle_material
		
		# Set up mesh for particles
		var cube_mesh = BoxMesh.new()
		cube_mesh.size = Vector3(0.2, 0.2, 0.2)
		particles.draw_pass_1 = cube_mesh
		
		# Configure particles
		particles.amount = 30
		particles.one_shot = true
		particles.explosiveness = 0.9
		particles.emitting = true
	
	# Disable collision
	set_collision_layer_value(1, false)
	set_collision_mask_value(1, false)
	
	# Remove after a short delay
	await get_tree().create_timer(1.0).timeout
	queue_free()

# Debug key to test damage
func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_G:
		print("Testing enemy damage")
		take_damage(25.0)
