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

func _process(_delta):
	if player and player.has_method("get") and player.get("current_health") != null:
		var current_health = player.current_health
		var max_health = player.max_health
		
		# Update health bar
		if health_bar:
			health_bar.value = (current_health / max_health) * 100
		
		# Update health text
		if health_label:
			health_label.text = str(int(current_health)) + " / " + str(int(max_health))
