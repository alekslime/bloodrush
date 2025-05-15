extends Node

# Wave properties
@export var starting_wave := 1
@export var enemies_per_wave := 3
@export var enemy_increase_per_wave := 2
@export var max_enemies_per_wave := 30
@export var time_between_waves := 5.0
@export var spawn_delay := 0.5  # Delay between individual enemy spawns

# Enemy types - add more as you create them
@export var enemy_scenes: Array[PackedScene] = []
@export var boss_scenes: Array[PackedScene] = []

# Spawn points
@export var spawn_points: Array[NodePath] = []
var spawn_point_nodes: Array[Node3D] = []

# Wave tracking
var current_wave := 0
var enemies_remaining := 0
var total_enemies_spawned := 0
var wave_in_progress := false
var between_waves := false
var wave_timer := 0.0
var spawn_timer := 0.0

# UI references
@onready var wave_label = $WaveUI/WaveLabel if has_node("WaveUI/WaveLabel") else null
@onready var enemy_count_label = $WaveUI/EnemyCountLabel if has_node("WaveUI/EnemyCountLabel") else null
@onready var wave_announcement = $WaveUI/WaveAnnouncement if has_node("WaveUI/WaveAnnouncement") else null

# Audio
@onready var wave_start_sound = $WaveStartSound if has_node("WaveStartSound") else null
@onready var wave_complete_sound = $WaveCompleteSound if has_node("WaveCompleteSound") else null

# Signals
signal wave_started(wave_number)
signal wave_completed(wave_number)
signal all_waves_completed

func _ready():
	# Get spawn point nodes from paths
	for path in spawn_points:
		var node = get_node(path)
		if node:
			spawn_point_nodes.append(node)
	
	# If no spawn points were set, try to find them by group
	if spawn_point_nodes.size() == 0:
		var points = get_tree().get_nodes_in_group("enemy_spawn_point")
		for point in points:
			if point is Node3D:
				spawn_point_nodes.append(point)
	
	# Verify we have enemy scenes
	if enemy_scenes.size() == 0:
		push_error("No enemy scenes assigned to WaveManager!")
		return
	
	# Setup UI
	setup_ui()
	
	# Start the first wave after a short delay
	current_wave = starting_wave - 1  # Will be incremented when starting
	wave_timer = 2.0  # Initial delay before first wave
	between_waves = true
	
	print("Wave Manager initialized with ", spawn_point_nodes.size(), " spawn points and ", enemy_scenes.size(), " enemy types")

func _process(delta):
	if between_waves:
		wave_timer -= delta
		if wave_timer <= 0:
			start_next_wave()
	elif wave_in_progress:
		# Check if all enemies are defeated
		if enemies_remaining <= 0 and total_enemies_spawned > 0:
			complete_wave()
		
		# Handle enemy spawning with delay
		if spawn_timer > 0:
			spawn_timer -= delta
			if spawn_timer <= 0 and enemies_remaining > 0:
				spawn_enemy()
				spawn_timer = spawn_delay
	
	# Update UI
	update_ui()

func start_next_wave():
	current_wave += 1
	between_waves = false
	wave_in_progress = true
	
	# Calculate number of enemies for this wave
	var num_enemies = min(
		enemies_per_wave + (current_wave - 1) * enemy_increase_per_wave,
		max_enemies_per_wave
	)
	
	enemies_remaining = num_enemies
	total_enemies_spawned = 0
	
	# Play wave start sound
	if wave_start_sound:
		wave_start_sound.play()
	
	# Show wave announcement
	show_wave_announcement()
	
	# Start spawning enemies
	spawn_timer = 1.0  # Initial delay before first enemy
	
	# Emit signal
	emit_signal("wave_started", current_wave)
	
	print("Wave ", current_wave, " started with ", num_enemies, " enemies")

func complete_wave():
	wave_in_progress = false
	between_waves = true
	wave_timer = time_between_waves
	
	# Play wave complete sound
	if wave_complete_sound:
		wave_complete_sound.play()
	
	# Emit signal
	emit_signal("wave_completed", current_wave)
	
	print("Wave ", current_wave, " completed!")

func spawn_enemy():
	if spawn_point_nodes.size() == 0:
		push_error("No spawn points available!")
		return
	
	# Select a random spawn point
	var spawn_point = spawn_point_nodes[randi() % spawn_point_nodes.size()]
	
	# Select enemy type based on wave number
	var enemy_scene
	
	# Every 5 waves, spawn a boss if available
	if current_wave % 5 == 0 and boss_scenes.size() > 0:
		var boss_index = min((current_wave / 5) - 1, boss_scenes.size() - 1)
		enemy_scene = boss_scenes[boss_index]
	else:
		# Gradually introduce more difficult enemies as waves progress
		var available_enemies = min(current_wave, enemy_scenes.size())
		var enemy_index = randi() % available_enemies
		enemy_scene = enemy_scenes[enemy_index]
	
	# Instance the enemy
	var enemy = enemy_scene.instantiate()
	get_tree().root.add_child(enemy)
	
	# Position at spawn point
	enemy.global_position = spawn_point.global_position
	
	# Add to enemy group
	enemy.add_to_group("enemy")
	
	# Connect to death signal or monitor for death
	if enemy.has_signal("enemy_died"):
		enemy.connect("enemy_died", _on_enemy_died)
	else:
		# If no signal, we'll rely on the _process check for enemies_remaining
		pass
	
	# Increment counter
	total_enemies_spawned += 1
	
	# Decrement remaining counter
	enemies_remaining -= 1
	
	print("Spawned enemy at ", spawn_point.name, ", remaining to spawn: ", enemies_remaining)
	
	# Scale enemy properties based on wave
	if enemy.has_method("set_difficulty_multiplier"):
		var difficulty = 1.0 + (current_wave - 1) * 0.1  # 10% increase per wave
		enemy.set_difficulty_multiplier(difficulty)
	
	# Directly modify enemy properties
	if "max_health" in enemy:
		enemy.max_health *= 1.0 + (current_wave - 1) * 0.2  # 20% health increase per wave
		enemy.current_health = enemy.max_health
	
	if "damage" in enemy:
		enemy.damage *= 1.0 + (current_wave - 1) * 0.1  # 10% damage increase per wave
	
	if "move_speed" in enemy:
		# Increase speed more slowly
		enemy.move_speed *= 1.0 + (current_wave - 1) * 0.05  # 5% speed increase per wave
	

func _on_enemy_died():
	# This is called when an enemy dies, if they emit the signal
	print("Enemy died")

func setup_ui():
	# Create UI if it doesn't exist
	if !has_node("WaveUI"):
		var ui = CanvasLayer.new()
		ui.name = "WaveUI"
		add_child(ui)
		
		# Wave label
		var wave_lbl = Label.new()
		wave_lbl.name = "WaveLabel"
		wave_lbl.text = "Wave: 1"
		wave_lbl.position = Vector2(20, 20)
		ui.add_child(wave_lbl)
		wave_label = wave_lbl
		
		# Enemy count label
		var enemy_lbl = Label.new()
		enemy_lbl.name = "EnemyCountLabel"
		enemy_lbl.text = "Enemies: 0"
		enemy_lbl.position = Vector2(20, 50)
		ui.add_child(enemy_lbl)
		enemy_count_label = enemy_lbl
		
		# Wave announcement
		var announcement = Label.new()
		announcement.name = "WaveAnnouncement"
		announcement.text = "WAVE 1"
		announcement.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		announcement.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		announcement.position = Vector2(512, 300)  # Center of screen
		announcement.modulate = Color(1, 1, 1, 0)  # Start transparent
		announcement.add_theme_font_size_override("font_size", 64)
		ui.add_child(announcement)
		wave_announcement = announcement

func update_ui():
	if wave_label:
		wave_label.text = "Wave: " + str(current_wave)
	
	if enemy_count_label:
		var enemies_alive = get_tree().get_nodes_in_group("enemy").size()
		enemy_count_label.text = "Enemies: " + str(enemies_alive)

func show_wave_announcement():
	if wave_announcement:
		wave_announcement.text = "WAVE " + str(current_wave)
		
		# Create animation
		var tween = create_tween()
		tween.tween_property(wave_announcement, "modulate", Color(1, 1, 1, 1), 0.5)
		tween.tween_interval(1.5)
		tween.tween_property(wave_announcement, "modulate", Color(1, 1, 1, 0), 0.5)

# Call this to manually start the wave system
func start_waves():
	if !wave_in_progress and !between_waves:
		between_waves = true
		wave_timer = 2.0

# Call this to manually stop the wave system
func stop_waves():
	wave_in_progress = false
	between_waves = false

# Call this to manually spawn a specific enemy
func spawn_specific_enemy(enemy_index: int, at_position: Vector3):
	if enemy_index < 0 or enemy_index >= enemy_scenes.size():
		push_error("Invalid enemy index!")
		return
		
	var enemy_scene = enemy_scenes[enemy_index]
	var enemy = enemy_scene.instantiate()
	get_tree().root.add_child(enemy)
	enemy.global_position = at_position
	enemy.add_to_group("enemy")
