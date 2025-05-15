extends Control

@export var player_path: NodePath
@onready var player = get_node(player_path) if player_path else null
@onready var health_bar = $HealthBar
@onready var health_label = $HealthLabel

func _ready():
	# If player path not set, try to find player
	if !player:
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player = players[0]
			print("HealthDisplay found player: ", player.name)

func _process(_delta):
	if player and player.has_method("get") and player.get("current_health") != null:
		var current_health = player.current_health
		var max_health = player.max_health
		
		# Update health bar
		if health_bar:
			health_bar.value = (current_health / max_health) * 100
			health_bar.modulate = Color(1.0, 0.2, 0.2) if current_health < max_health * 0.3 else Color(1.0, 1.0, 1.0)
		
		# Update health text
		if health_label:
			health_label.text = str(int(current_health)) + " / " + str(int(max_health))
			
			# Flash text redw when health is low
			if current_health < max_health * 0.3:
				health_label.modulate = Color(1.0, 0.0, 0.0)
			else:
				health_label.modulate = Color(1.0, 1.0, 1.0)
