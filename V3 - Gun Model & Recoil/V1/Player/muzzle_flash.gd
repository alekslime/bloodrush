extends Node3D

func _ready() -> void:
	# Start particles
	if has_node("CPUParticles3D"):
		$CPUParticles3D.emitting = true
	
	# Flash light briefly
	if has_node("OmniLight3D"):
		$OmniLight3D.visible = true
		var tween = create_tween()
		tween.tween_property($OmniLight3D, "light_energy", 0.0, 0.1)
