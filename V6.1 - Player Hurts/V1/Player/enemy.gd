extends CharacterBody3D

# Enemy properties
@export var move_speed := 3.0
@export var damage := 20.0
@export var attack_cooldown := 1.0
@export var max_health := 100.0
var current_health := 100.0

# References
@onready var mesh_instance = $MeshInstance3D if has_node("MeshInstance3D") else null

# State tracking
var player = null
var attack_timer := 0.0
var is_dead := false

func _ready():
	# Initialize health
	current_health = max_health
	
	# Find player
	find_player()
	
	# Add to enemy group
	add_to_group("enemy")
	
	# Setup hit area
	setup_hit_area()
	
	# Add debug label
	add_debug_label()
	
	print("Enemy initialized with health: ", current_health)

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
		if node is MovementController:
			player = node
			print("Found player by class: ", player.name)
			# Add to player group for future detection
			player.add_to_group("player")
			return
	
	# Last resort - find any node with the right script
	var root = get_tree().root
	for child in root.get_children():
		if child.get_script() and child.get_script().resource_path.find("MovementController") >= 0:
			player = child
			print("Found player by script: ", player.name)
			player.add_to_group("player")
			return
	
	print("WARNING: No player found!")

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

func add_debug_label():
	# Check for existing label
	var label = get_node_or_null("DebugLabel")
	
	# Create new label if needed
	if !label:
		label = Label3D.new()
		label.name = "DebugLabel"
		add_child(label)
		label.position = Vector3(0, 2.5, 0)
		label.billboard = true
		label.font_size = 16
		label.modulate = Color(1, 0, 0)  # Red
	
	# Update label text
	label.text = "Health: " + str(current_health)

func update_debug_label():
	var label = get_node_or_null("DebugLabel")
	if label:
		label.text = "Health: " + str(current_health)

func _physics_process(delta):
	# Skip if dead
	if is_dead:
		return
	
	# Update attack cooldown timer
	if attack_timer > 0:
		attack_timer -= delta
	
	# Skip if no player
	if !player:
		find_player()
		return
	
	# Simple direct movement toward player
	var direction = (player.global_position - global_position).normalized()
	direction.y = 0  # Keep on XZ plane
	
	# Set velocity
	velocity = direction * move_speed
	
	# Rotate toward player
	look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z), Vector3.UP)
	
	# Move
	move_and_slide()
	
	# Check for collisions with player
	for i in range(get_slide_collision_count()):
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()
		
		if collider == player and attack_timer <= 0:
			print("Enemy collided with player! Attacking...")
			attack_player(player)

func _on_hit_area_area_entered(area):
	# Skip if dead
	if is_dead:
		return
	
	# Safety check for null
	if area == null:
		print("WARNING: Null area entered hit area")
		return
	
	print("Area entered hit area: ", area.name)
	
	# Check if it's a player weapon
	if area.has_method("is_in_group") and area.is_in_group("player_weapon"):
		print("Hit by player weapon!")
		take_damage(25.0)
	else:
		print("Area is not a player weapon. Groups: ", area.get_groups() if area.has_method("get_groups") else "unknown")

func attack_player(player_body):
	# Skip if dead
	if is_dead:
		return
	
	print("Enemy attacking player!")
	
	# Apply damage to player
	if player_body.has_method("take_damage"):
		player_body.take_damage(damage)
		print("Dealt ", damage, " damage to player")
	else:
		print("WARNING: Player doesn't have take_damage method!")
	
	print("ATTACKING PLAYER NOW!")
	# Start attack cooldown
	attack_timer = attack_cooldown

func take_damage(amount):
	# Skip if dead
	if is_dead:
		return
	
	print("Enemy taking damage: ", amount)
	current_health -= amount
	print("Enemy health: ", current_health, "/", max_health)
	
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
		die()

func die():
	print("Enemy died!")
	is_dead = true
	
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
	
	# Disable movement
	set_physics_process(false)
	
	# Remove after a short delay
	await get_tree().create_timer(1.0).timeout
	queue_free()

# Debug key to test damage
func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_G:
		print("Testing enemy damage")
		take_damage(25.0)
