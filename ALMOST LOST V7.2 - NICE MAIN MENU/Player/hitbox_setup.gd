extends Area3D

func _ready():
	# Make sure we're in the player_weapon group
	if !is_in_group("player_weapon"):
		add_to_group("player_weapon")
		print("Hitbox added itself to player_weapon group")
	
	# Connect the area_entered signal if not already connected
	if !is_connected("area_entered", _on_area_entered):
		connect("area_entered", _on_area_entered)
	
	print("Hitbox initialized with groups: ", get_groups())

func _on_area_entered(area):
	print("Hitbox detected area: ", area.name)
	
	# Check if we hit an enemy
	if area.is_in_group("enemy_hitbox"):
		print("Hitbox hit enemy area!")
		
		# Find the enemy parent
		var parent = area.get_parent()
		if parent and parent.has_method("take_damage"):
			parent.take_damage(25.0)
			print("Applied damage to enemy")
