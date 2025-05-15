extends CanvasLayer

@onready var debug_label = $DebugLabel
@onready var fps_label = $FPSLabel
@onready var player = get_tree().get_nodes_in_group("player")[0] if get_tree().get_nodes_in_group("player").size() > 0 else null

var debug_enabled := true

func _ready():
	# Set up debug label
	if debug_label:
		debug_label.text = "Debug Info"
	
	# Toggle visibility based on debug setting
	visible = debug_enabled

func _process(_delta):
	if Input.is_action_just_pressed("toggle_debug"):
		debug_enabled = !debug_enabled
		visible = debug_enabled
	
	update_debug_info()
	update_fps()

func update_debug_info():
	if !debug_label or !player:
		return
	
	var debug_text = "Player Info:\n"
	debug_text += "Position: " + str(player.global_position) + "\n"
	debug_text += "Velocity: " + str(player.velocity) + "\n"
	debug_text += "Speed: " + str(player.velocity.length()) + "\n"
	debug_text += "Health: " + str(player.current_health) + "/" + str(player.max_health) + "\n"
	debug_text += "\nGame State:\n"
	debug_text += "Enemies: " + str(get_tree().get_nodes_in_group("enemy").size()) + "\n"
	
	# Add collision info
	debug_text += "\nCollision Info:\n"
	if player.is_on_floor():
		debug_text += "On Floor: Yes\n"
	else:
		debug_text += "On Floor: No\n"
	
	debug_label.text = debug_text

func update_fps():
	if fps_label:
		fps_label.text = "FPS: " + str(Engine.get_frames_per_second())
