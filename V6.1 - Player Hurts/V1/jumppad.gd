extends Area3D

@export var jump_force: float = 90.0
@export var forward_force: float = 0.0
@export var override_movement_states: bool = true  # New parameter to force override

func _ready():
	body_entered.connect(_on_jumppad_body_entered)
	
	# Visual material setup
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.5, 0.0)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.5, 0.0)
	material.emission_energy = 1.0  # Changed from emission_energy_multiplier
	
	if get_child_count() > 1 and get_child(1) is MeshInstance3D:
		get_child(1).material_override = material

func _on_jumppad_body_entered(body):
	print("Body entered jumppad: ", body.name)
	
	# Check if it's a MovementController
	if body.has_method("_on_jumppad_contact"):
		print("Calling jumppad contact method with force: ", jump_force)
		body._on_jumppad_contact(jump_force, forward_force, override_movement_states)
	# Fallback for any physics body
	elif body.has_method("get") and body.get("velocity") != null:
		print("Applying jump force directly: ", jump_force)
		body.velocity.y = jump_force
		
		if forward_force > 0:
			var forward_dir = -global_transform.basis.z.normalized()
			body.velocity.x += forward_dir.x * forward_force
			body.velocity.z += forward_dir.z * forward_force
