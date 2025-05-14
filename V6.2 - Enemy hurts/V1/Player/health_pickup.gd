extends Area3D

@export var health_amount := 25.0
@export var respawn_time := 30.0
@export var bob_height := 0.5
@export var bob_speed := 2.0
@export var rotation_speed := 1.0

@onready var mesh_instance = $MeshInstance3D if has_node("MeshInstance3D") else null
@onready var collision_shape = $CollisionShape3D if has_node("CollisionShape3D") else null
@onready var particles = $GPUParticles3D if has_node("GPUParticles3D") else null

var original_y := 0.0
var time_passed := 0.0
var is_active := true

func _ready():
	# Store original height
	original_y = global_position.y
	
	# Connect signal
	connect("body_entered", _on_body_entered)
	
	# Create mesh if it doesn't exist
	if !mesh_instance:
		mesh_instance = MeshInstance3D.new()
		add_child(mesh_instance)
		
		# Create a heart-shaped mesh or use a simple shape
		var mesh = SphereMesh.new()
		mesh.radius = 0.3
		mesh.height = 0.6
		mesh_instance.mesh = mesh
		
		# Create material
		var material = StandardMaterial3D.new()
		material.albedo_color = Color(1.0, 0.2, 0.2)  # Red
		material.emission_enabled = true
		material.emission = Color(1.0, 0.2, 0.2)
		material.emission_energy = 1.0
		mesh_instance.material_override = material
	
	# Create collision shape if it doesn't exist
	if !collision_shape:
		collision_shape = CollisionShape3D.new()
		add_child(collision_shape)
		
		var shape = SphereShape3D.new()
		shape.radius = 0.5
		collision_shape.shape = shape
	
	# Create particles if they don't exist
	if !particles:
		particles = GPUParticles3D.new()
		add_child(particles)
		
		# Set up particle material
		var particle_material = ParticleProcessMaterial.new()
		particle_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		particle_material.emission_sphere_radius = 0.3
		particle_material.direction = Vector3(0, 1, 0)
		particle_material.spread = 180.0
		particle_material.initial_velocity_min = 0.5
		particle_material.initial_velocity_max = 1.0
		particle_material.gravity = Vector3(0, -0.5, 0)
		particle_material.color = Color(1.0, 0.2, 0.2)  # Red
		
		particles.process_material = particle_material
		
		# Set up mesh for particles
		var particle_mesh = SphereMesh.new()
		particle_mesh.radius = 0.05
		particle_mesh.height = 0.1
		particles.draw_pass_1 = particle_mesh
		
		# Configure particles
		particles.amount = 16
		particles.lifetime = 1.0
		particles.emitting = true

func _process(delta):
	if !is_active:
		return
	
	# Update time
	time_passed += delta
	
	# Bob up and down
	global_position.y = original_y + sin(time_passed * bob_speed) * bob_height
	
	# Rotate
	rotate_y(rotation_speed * delta)

func _on_body_entered(body):
	if !is_active:
		return
	
	# Check if it's the player
	if body.is_in_group("player") and body.has_method("heal"):
		print("Player collected health pickup")
		
		# Apply healing
		body.heal(health_amount)
		
		# Deactivate pickup
		deactivate()
		
		# Respawn after delay
		if respawn_time > 0:
			await get_tree().create_timer(respawn_time).timeout
			activate()

func deactivate():
	is_active = false
	
	# Hide mesh
	if mesh_instance:
		mesh_instance.visible = false
	
	# Disable collision
	if collision_shape:
		collision_shape.disabled = true
	
	# Stop particles
	if particles:
		particles.emitting = false
	
	# Play pickup effect
	play_pickup_effect()

func activate():
	is_active = true
	
	# Show mesh
	if mesh_instance:
		mesh_instance.visible = true
	
	# Enable collision
	if collision_shape:
		collision_shape.disabled = false
	
	# Start particles
	if particles:
		particles.emitting = true

func play_pickup_effect():
	# Create a one-shot particle effect
	var pickup_particles = GPUParticles3D.new()
	get_parent().add_child(pickup_particles)
	pickup_particles.global_position = global_position
	
	# Set up particle material
	var particle_material = ParticleProcessMaterial.new()
	particle_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	particle_material.emission_sphere_radius = 0.1
	particle_material.direction = Vector3(0, 1, 0)
	particle_material.spread = 180.0
	particle_material.initial_velocity_min = 2.0
	particle_material.initial_velocity_max = 5.0
	particle_material.gravity = Vector3(0, -1.0, 0)
	particle_material.color = Color(1.0, 0.5, 0.5)  # Light red
	
	pickup_particles.process_material = particle_material
	
	# Set up mesh for particles
	var particle_mesh = SphereMesh.new()
	particle_mesh.radius = 0.05
	particle_mesh.height = 0.1
	pickup_particles.draw_pass_1 = particle_mesh
	
	# Configure particles
	pickup_particles.amount = 20
	pickup_particles.lifetime = 0.5
	pickup_particles.one_shot = true
	pickup_particles.explosiveness = 0.9
	pickup_particles.emitting = true
	
	# Auto-remove after effect is done
	await get_tree().create_timer(1.0).timeout
	pickup_particles.queue_free()
