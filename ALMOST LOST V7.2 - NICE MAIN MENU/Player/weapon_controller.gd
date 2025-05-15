extends Node3D

@export var damage := 25.0
@export var fire_rate := 0.2
@export var range := 100.0
@export var knockback_force := 10.0

@onready var camera = $"../Camera" # Adjust path to your camera
@onready var raycast = $RayCast3D
@onready var animation_player = $AnimationPlayer
@onready var muzzle_flash = $MuzzleFlash
@onready var impact_particles = preload("res://effects/impact_particles.tscn")
@onready var bullet_trail = preload("res://effects/bullet_trail.tscn")

var can_fire := true
var fire_timer :=	 0.0

func _ready():
	# Setup raycast if it doesn't exist
	if !raycast:
		raycast = RayCast3D.new()
		add_child(raycast)
		raycast.enabled = true
		raycast.target_position = Vector3(0, 0, -range)
		raycast.collision_mask = 1 # Adjust to your collision layers

func _process(delta):
	# Update fire timer
	if !can_fire:
		fire_timer += delta
		if fire_timer >= fire_rate:
			can_fire = true
			fire_timer = 0.0
	
	# Handle firing
	if Input.is_action_pressed("attack") and can_fire:
		fire_weapon()

func fire_weapon():
	can_fire = false
	
	# Play attack animation
	if animation_player and animation_player.has_animation("attack"):
		animation_player.play("attack")
	
	# Show muzzle flash
	if muzzle_flash:
		muzzle_flash.emitting = true
	
	# Force raycast to update
	raycast.force_raycast_update()
	
	# Check for hit
	if raycast.is_colliding():
		var hit_point = raycast.get_collision_point()
		var hit_normal = raycast.get_collision_normal()
		var collider = raycast.get_collider()
		
		print("Hit: ", collider.name, " at position: ", hit_point)
		
		# Create impact effect
		spawn_impact_effect(hit_point, hit_normal)
		
		# Create bullet trail
		spawn_bullet_trail(global_position, hit_point)
		
		# Apply damage if it's an enemy
		if collider.is_in_group("enemy") and collider.has_method("take_damage"):
			collider.take_damage(damage)
			print("Applied damage to enemy")
			
			# Apply knockback if it's a physics body
			if collider is RigidBody3D:
				var knockback_direction = (hit_point - global_position).normalized()
				collider.apply_impulse(knockback_direction * knockback_force)
	else:
		# Create bullet trail to max range if nothing was hit
		var end_point = global_position + -global_transform.basis.z * range
		spawn_bullet_trail(global_position, end_point)

func spawn_impact_effect(position, normal):
	var impact = impact_particles.instantiate()
	get_tree().root.add_child(impact)
	impact.global_position = position
	impact.global_transform.basis = Basis(normal.cross(Vector3.UP).normalized(), normal, normal.cross(Vector3.UP).cross(normal).normalized())
	impact.emitting = true
	
	# Auto-remove after effect is done
	var timer = Timer.new()
	impact.add_child(timer)
	timer.wait_time = 2.0
	timer.one_shot = true
	timer.timeout.connect(func(): impact.queue_free())
	timer.start()

func spawn_bullet_trail(start_pos, end_pos):
	var trail = bullet_trail.instantiate()
	get_tree().root.add_child(trail)
	
	# Set trail positions
	trail.points[0] = start_pos
	trail.points[1] = end_pos
	
	# Auto-remove after effect is done
	var timer = Timer.new()
	trail.add_child(timer)
	timer.wait_time = 0.1
	timer.one_shot = true
	timer.timeout.connect(func(): trail.queue_free())
	timer.start()
