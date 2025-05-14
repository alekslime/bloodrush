extends CharacterBody3D

# Enemy properties
@export var move_speed := 8.0
@export var damage := 20.0
@export var attack_cooldown := 1.0
@export var max_health := 300.0
@export var attack_range := 6.0
@export var detection_range := 100.0
@export var stagger_threshold := 50.0

# Movement properties
@export var acceleration := 10.0
@export var rotation_speed := 8.0

var current_health := max_health
var stagger_amount := 0.0
var is_dead := false
var attack_timer := 0.0
var attack_area: Area3D

# State machine
enum State {IDLE, CHASE, ATTACK, STAGGER, DEAD}
var current_state = State.IDLE

# References
@onready var mesh_instance = $MeshInstance3D
@onready var animation_player = $AnimationPlayer if has_node("AnimationPlayer") else null
@onready var state_timer := 0.0
@onready var debug_label = $DebugLabel if has_node("DebugLabel") else null

# Navigation
@onready var nav_agent = $NavigationAgent3D
var path_update_timer := 0.0
const PATH_UPDATE_INTERVAL := 0.2

# Target
var player: Node3D = null

func _ready():
	current_health = max_health
	add_to_group("enemies")
	
	# Setup navigation
	if nav_agent:
		nav_agent.path_max_distance = detection_range * 1.5
		nav_agent.path_desired_distance = 0.5
		nav_agent.target_desired_distance = attack_range * 0.8
	
	setup_hit_area()
	setup_attack_area()
	setup_debug_label()
	
	# Initial player search
	find_player()
	print("Enemy initialized at: ", global_position)

func setup_debug_label():
	if !debug_label:
		debug_label = Label3D.new()
		debug_label.name = "DebugLabel"
		add_child(debug_label)
		debug_label.position = Vector3(0, 2, 0)
		debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		debug_label.font_size = 48
		debug_label.modulate = Color.RED

func setup_hit_area():
	var hit_area = get_node_or_null("HitArea")
	if !hit_area:
		hit_area = Area3D.new()
		hit_area.name = "HitArea"
		add_child(hit_area)
		
		var shape = CapsuleShape3D.new()
		shape.radius = 0.5
		shape.height = 2.0
		var collision = CollisionShape3D.new()
		collision.shape = shape
		hit_area.add_child(collision)
	
	hit_area.add_to_group("enemy_hitbox")
	if !hit_area.area_entered.is_connected(_on_hit_area_area_entered):
		hit_area.area_entered.connect(_on_hit_area_area_entered)

func setup_attack_area():
	attack_area = Area3D.new()
	attack_area.name = "AttackArea"
	add_child(attack_area)
	
	var shape = SphereShape3D.new()
	shape.radius = attack_range * 0.9
	var collision = CollisionShape3D.new()
	collision.shape = shape
	attack_area.add_child(collision)
	
	attack_area.collision_mask = 2 # Should match player layer
	attack_area.body_entered.connect(_on_attack_area_body_entered)

func _physics_process(delta):
	if current_state == State.DEAD:
		return
	
	# Update timers
	update_timers(delta)
	
	# State machine
	process_state(delta)
	
	# Apply movement
	move_and_slide()
	
	# Debug
	update_debug_label()

func update_timers(delta):
	attack_timer = max(attack_timer - delta, 0)
	state_timer = max(state_timer - delta, 0)
	path_update_timer = max(path_update_timer - delta, 0)
	
	if stagger_amount > 0:
		stagger_amount = max(stagger_amount - delta * 10.0, 0)

func process_state(delta):
	if !player:
		find_player()
		if !player:
			current_state = State.IDLE
			return
	
	match current_state:
		State.IDLE:
			process_idle_state(delta)
		State.CHASE:
			process_chase_state(delta)
		State.ATTACK:
			process_attack_state(delta)
		State.STAGGER:
			process_stagger_state(delta)

func process_idle_state(delta):
	if player and global_position.distance_to(player.global_position) < detection_range:
		change_state(State.CHASE)
		return
	
	# Idle wandering
	if state_timer <= 0:
		state_timer = randf_range(2.0, 4.0)
		velocity = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * move_speed * 0.3
	else:
		velocity = velocity.move_toward(Vector3.ZERO, acceleration * delta)

func process_chase_state(delta):
	var distance_to_player = global_position.distance_to(player.global_position)
	
	if distance_to_player > detection_range * 1.2:
		change_state(State.IDLE)
		return
	
	if distance_to_player < attack_range and attack_timer <= 0:
		change_state(State.ATTACK)
		return
	
	# Update navigation path
	if path_update_timer <= 0 and nav_agent:
		nav_agent.target_position = player.global_position
		path_update_timer = PATH_UPDATE_INTERVAL
	
	# Movement
	var target_velocity = Vector3.ZERO
	
	if nav_agent and nav_agent.is_navigation_finished() == false:
		var next_pos = nav_agent.get_next_path_position()
		var direction = (next_pos - global_position).normalized()
		direction.y = 0
		
		target_velocity = direction * move_speed
		
		# Smooth rotation
		if direction.length() > 0.1:
			var target_angle = atan2(direction.x, direction.z)
			rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * delta)
	
	velocity = velocity.lerp(target_velocity, acceleration * delta)

func process_attack_state(delta):
	velocity = velocity.move_toward(Vector3.ZERO, acceleration * delta * 2)
	
	if state_timer <= 0:
		perform_attack()
		attack_timer = attack_cooldown
		change_state(State.CHASE)
	else:
		# Face player during attack windup
		if player:
			var direction = (player.global_position - global_position).normalized()
			direction.y = 0
			if direction.length() > 0.1:
				var target_angle = atan2(direction.x, direction.z)
				rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * 2 * delta)

func process_stagger_state(delta):
	if state_timer <= 0:
		change_state(State.CHASE)
	else:
		var knockback_dir = (global_position - player.global_position).normalized()
		knockback_dir.y = 0
		velocity = velocity.lerp(knockback_dir * move_speed * 0.5, acceleration * delta)

func change_state(new_state):
	if current_state == new_state:
		return
	
	current_state = new_state
	print("State changed to: ", State.keys()[new_state])
	
	match new_state:
		State.IDLE:
			state_timer = randf_range(1.0, 3.0)
		State.CHASE:
			if nav_agent:
				nav_agent.target_position = player.global_position
		State.ATTACK:
			state_timer = 0.3 # Attack windup time
			if animation_player and animation_player.has_animation("attack_windup"):
				animation_player.play("attack_windup")
		State.STAGGER:
			state_timer = 0.5
		State.DEAD:
			die()

func perform_attack():
	print("Attacking player!")
	
	if animation_player and animation_player.has_animation("attack"):
		animation_player.play("attack")
	
	if player and global_position.distance_to(player.global_position) < attack_range * 1.1:
		if player.has_method("take_damage"):
			player.take_damage(damage)

func find_player():
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]
		print("Found player: ", player.name)
		return true
	
	print("Player not found in 'player' group")
	return false

func take_damage(amount):
	if current_state == State.DEAD:
		return
	
	current_health -= amount
	stagger_amount += amount
	print("Took damage: ", amount, " | Health: ", current_health)
	
	# Visual feedback
	if mesh_instance:
		var original_mat = mesh_instance.get_surface_override_material(0)
		var hit_mat = StandardMaterial3D.new()
		hit_mat.albedo_color = Color.RED
		mesh_instance.set_surface_override_material(0, hit_mat)
		
		get_tree().create_timer(0.1).timeout.connect(
			func(): 
				if is_instance_valid(mesh_instance):
					mesh_instance.set_surface_override_material(0, original_mat)
		)
	
	if stagger_amount >= stagger_threshold:
		change_state(State.STAGGER)
		stagger_amount = 0
	
	if current_health <= 0:
		change_state(State.DEAD)
	
	update_debug_label()

func die():
	is_dead = true
	set_collision_layer_value(1, false)
	set_collision_mask_value(1, false)
	
	if animation_player and animation_player.has_animation("death"):
		animation_player.play("death")
	else:
		# Default death effect
		var tween = create_tween()
		tween.tween_property(mesh_instance, "scale", Vector3.ZERO, 0.5)
		tween.tween_callback(queue_free)
	
	print("Enemy died")

func update_debug_label():
	if debug_label:
		var state_name = State.keys()[current_state] if current_state < State.size() else "UNKNOWN"
		debug_label.text = "HP: %d\nState: %s" % [current_health, state_name]

# Signal handlers
func _on_hit_area_area_entered(area):
	if current_state == State.DEAD:
		return
	
	if area.is_in_group("player_weapon"):
		take_damage(25.0)
	elif area.is_in_group("player"):
		take_damage(10.0)

func _on_attack_area_body_entered(body):
	if body == player and current_state != State.ATTACK and attack_timer <= 0:
		change_state(State.ATTACK)

# Debug function
func _input(event):
	if event.is_action_pressed("debug_damage"):
		take_damage(25.0)
