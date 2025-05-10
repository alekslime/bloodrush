extends Node3D

func _ready() -> void:
	# Start particles
	if has_node("CPUParticles3D"):
		$CPUParticles3D.emitting = true
	
	# Flash light briefly
	if has_node("SpotLight3D"):
		$SpotLight3D.visible = true
		var tween = create_tween()
		tween.tween_property($SpotLight3D, "light_energy", 0.0, 0.1)
	
	# Auto-destroy after particles finish
	await get_tree().create_timer(1.0).timeout
	queue_free()
