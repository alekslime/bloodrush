extends Area3D

@export var jump_force: float = 90.0
@export var forward_force: float = 0.0

func _ready():
	# Connect the body entered signal directly in code to ensure it works
	body_entered.connect(_on_jumppad_body_entered)
	
	# Add a visual material to make the jumppad visible
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.5, 0.0)  # Orange color
	material.emission_enabled = true
	material.emission = Color(1.0, 0.5, 0.0)
	material.emission_energy_multiplier = 1.0
	
	# Apply material to the mesh
	if get_child_count() > 1 and get_child(1) is MeshInstance3D:
		get_child(1).material_override = material

func _on_jumppad_body_entered(body):
	# Print for debugging
	print("Body entered jumppad: ", body.name)
	
	# Check if the body has a velocity property (like CharacterBody3D)
	if body.has_method("get") and body.get("velocity") != null:
		print("Applying jump force: ", jump_force)
		
		# Apply vertical force
		body.velocity.y = jump_force
		
		# Apply forward force if specified
		if forward_force > 0:
			var forward_dir = -global_transform.basis.z.normalized()
			body.velocity.x += forward_dir.x * forward_force
			body.velocity.z += forward_dir.z * forward_force
		
		# If the body has a head node with camera shake, use it
		if body.has_node("Head") and body.get_node("Head").has_method("add_camera_shake"):
			body.get_node("Head").add_camera_shake(0.3, 0.2)
