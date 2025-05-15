extends Node3D

@onready var label_3d = $Label3D
@onready var animation_player = $AnimationPlayer

var damage_amount := 0.0
var critical_hit := false

func _ready():
	# Set up label
	if label_3d:
		update_label()
	
	# Play animation
	if animation_player and animation_player.has_animation("float_up"):
		animation_player.play("float_up")
	
	# Auto-destroy after animation
	await get_tree().create_timer(1.0).timeout
	queue_free()

func set_damage(amount: float, is_critical: bool = false):
	damage_amount = amount
	critical_hit = is_critical
	update_label()

func update_label():
	if label_3d:
		# Format damage text
		var damage_text = str(int(damage_amount))
		
		# Set color and size based on damage amount and critical status
		if critical_hit:
			label_3d.text = damage_text + "!"
			label_3d.modulate = Color(1.0, 0.2, 0.2)  # Bright red
			label_3d.font_size = 24
		else:
			label_3d.text = damage_text
			
			# Color based on damage amount
			if damage_amount > 50:
				label_3d.modulate = Color(1.0, 0.5, 0.0)  # Orange
				label_3d.font_size = 20
			else:
				label_3d.modulate = Color(1.0, 1.0, 1.0)  # White
				label_3d.font_size = 16
