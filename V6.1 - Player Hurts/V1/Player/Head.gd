extends Node3D

@export_node_path("Camera3D") var cam_path := NodePath("Camera")
@onready var cam: Camera3D = get_node(cam_path)

@export var mouse_sensitivity := 2.0
@export var y_limit := 90.0
var mouse_axis := Vector2()
var rot := Vector3()

#Sword
@onready var anim_player = $AnimationPlayer
#Hitbox
@onready var hitbox = $Camera/WeaponPivot/WeaponMesh/Sketchfab_Scene/Hitbox

# Slide camera variables
var is_sliding := false
var original_camera_y := 0.0
var slide_camera_y := 0.0
var camera_bob_amount := 0.05
var camera_bob_speed := 15.0
var camera_bob_timer := 0.0
var transition_speed := 15.0  # Speed of camera height transition

# Camera tilt variables
var max_tilt_angle := 10.0  # Maximum tilt angle in degrees
var current_tilt := 0.0
var target_tilt := 0.0
var tilt_direction := 1.0  # 1.0 for right, -1.0 for left
var slide_direction := Vector3.ZERO

# Grapple variables
var is_grappling := false
var grapple_target_valid := false
var grapple_reticle: Node2D
var grapple_camera_shake := 0.0
var grapple_camera_shake_amount := 0.05
var grapple_camera_shake_speed := 20.0
var grapple_camera_shake_decay := 5.0

# Ground pound variables
var is_ground_pounding := false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	mouse_sensitivity = mouse_sensitivity / 1000
	y_limit = deg_to_rad(y_limit)
	
	# Store original camera height
	original_camera_y = cam.position.y
	slide_camera_y = original_camera_y - 0.4  # Lower position during slide
	
	# Setup grapple raycast if it doesn't exist
	if !cam.has_node("GrappleRaycast"):
		var raycast = RayCast3D.new()
		raycast.name = "GrappleRaycast"
		cam.add_child(raycast)
		raycast.enabled = true
		raycast.target_position = Vector3(0, 0, -100)  # 100 units forward
		raycast.collision_mask = 1  # Adjust to your collision layers
	
	# Setup grapple reticle
	setup_grapple_reticle()

# Called when there is an input event
func _input(event: InputEvent) -> void:
	# Mouse look (only if the mouse is captured).
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		mouse_axis = event.relative
		camera_rotation()

# Called every physics tick. 'delta' is constant
func _physics_process(delta: float) -> void:
	var joystick_axis := Input.get_vector(&"look_left", &"look_right",
			&"look_down", &"look_up")
	
	
	if joystick_axis != Vector2.ZERO:
		mouse_axis = joystick_axis * 1000.0 * delta
		camera_rotation()
	
	# Handle camera position and tilt during slide
	if is_sliding:
		# Smooth transition to slide height
		cam.position.y = lerp(cam.position.y, slide_camera_y, delta * transition_speed)
		
		# Add slight camera bob for ULTRAKILL feel
		camera_bob_timer += delta * camera_bob_speed
		cam.position.y += sin(camera_bob_timer) * camera_bob_amount
		
		# Add slight forward tilt for speed feel
		cam.rotation.x = lerp(cam.rotation.x, deg_to_rad(5.0), delta * transition_speed)
		
		# Apply side tilt based on movement direction
		current_tilt = lerp(current_tilt, target_tilt, delta * transition_speed)
		cam.rotation.z = deg_to_rad(current_tilt * tilt_direction)
		
		# Add slight camera sway based on steering
		var owner_node = get_owner()
		if owner_node and owner_node.direction.length() > 0.1:
			# Calculate dot product to determine left/right movement
			var right_vector = owner_node.transform.basis.x
			var dot_product = right_vector.dot(owner_node.direction)
			
			# Apply slight additional tilt based on steering direction
			cam.rotation.z += deg_to_rad(dot_product * 2.0)
	elif is_ground_pounding:
		# Apply camera effects during ground pound
		# Forward tilt to look at the ground
		cam.rotation.x = lerp(cam.rotation.x, deg_to_rad(30.0), delta * transition_speed)
		
		# Add slight camera shake
		cam.position.x = sin(Time.get_ticks_msec() * 0.03) * 0.02
		cam.position.y = original_camera_y + sin(Time.get_ticks_msec() * 0.02) * 0.02
	elif is_grappling:
		# Apply camera shake during grappling
		if grapple_camera_shake > 0:
			grapple_camera_shake -= delta * grapple_camera_shake_decay
			cam.position.x = sin(Time.get_ticks_msec() * 0.02) * grapple_camera_shake * grapple_camera_shake_amount
			cam.position.y = original_camera_y + sin(Time.get_ticks_msec() * 0.015) * grapple_camera_shake * grapple_camera_shake_amount
		else:
			cam.position.x = lerp(cam.position.x, 0.0, delta * transition_speed)
			cam.position.y = lerp(cam.position.y, original_camera_y, delta * transition_speed)
	else:
		# Smooth transition back to normal height and rotation
		cam.position.x = lerp(cam.position.x, 0.0, delta * transition_speed)
		cam.position.y = lerp(cam.position.y, original_camera_y, delta * transition_speed)
		cam.rotation.x = lerp(cam.rotation.x, 0.0, delta * transition_speed)
		current_tilt = lerp(current_tilt, 0.0, delta * transition_speed)
		cam.rotation.z = deg_to_rad(current_tilt * tilt_direction)
	
	# Update grapple reticle
	update_grapple_reticle()

func camera_rotation() -> void:
	# Horizontal mouse look.
	rot.y -= mouse_axis.x * mouse_sensitivity
	# Vertical mouse look.
	rot.x = clamp(rot.x - mouse_axis.y * mouse_sensitivity, -y_limit, y_limit)
	
	get_owner().rotation.y = rot.y
	rotation.x = rot.x

# Called from movement controller to tilt camera during slide
func tilt_for_slide(direction: Vector3) -> void:
	is_sliding = true
	camera_bob_timer = 0.0  # Reset bob timer
	slide_direction = direction
	
	# Calculate tilt direction based on slide direction
	var owner_node = get_owner()
	if owner_node:
		var right_vector = owner_node.transform.basis.x
		var dot_product = right_vector.dot(direction)
		
		# Set tilt direction based on movement
		tilt_direction = -sign(dot_product)  # Negative because we tilt opposite to movement
		target_tilt = max_tilt_angle  # Set target tilt angle

# Reset camera when slide ends
func reset_from_slide() -> void:
	is_sliding = false
	target_tilt = 0.0

# Set grappling state
func set_grappling(grappling: bool) -> void:
	is_grappling = grappling
	
	if grappling:
		# Add initial camera shake when grapple starts
		grapple_camera_shake = 1.0

# Set ground pounding state
func set_ground_pounding(pounding: bool) -> void:
	is_ground_pounding = pounding
	
	if pounding:
		# Add forward tilt to camera for ground pound
		var tween = create_tween()
		tween.tween_property(cam, "rotation:x", deg_to_rad(30.0), 0.2)
	else:
		# Reset camera tilt
		var tween = create_tween()
		tween.tween_property(cam, "rotation:x", 0.0, 0.3)

# Add camera shake (can be called from other scripts)
func add_camera_shake(amount: float, duration: float = 0.3) -> void:
	grapple_camera_shake = max(grapple_camera_shake, amount)
	grapple_camera_shake_decay = amount / duration

# Setup the grapple reticle UI
func setup_grapple_reticle() -> void:
	# Create a Control node for the reticle
	var control = Control.new()
	control.name = "GrappleReticle"
	control.set_anchors_preset(Control.PRESET_CENTER)
	cam.add_child(control)
	
	# Create the reticle
	grapple_reticle = Node2D.new()
	grapple_reticle.name = "Reticle"
	control.add_child(grapple_reticle)
	
	# Connect the draw signal
	grapple_reticle.connect("draw", _on_reticle_draw)

# Update the grapple reticle based on raycast hit
func update_grapple_reticle() -> void:
	if !grapple_reticle:
		return
	
	var raycast = cam.get_node("GrappleRaycast") as RayCast3D
	if raycast:
		# Check if raycast is hitting something
		if raycast.is_colliding():
			var collider = raycast.get_collider()
			
			# Check if the object is grappleable
			if collider is StaticBody3D or "grappleable" in collider.get_groups():
				grapple_target_valid = true
			else:
				grapple_target_valid = false
		else:
			grapple_target_valid = false
		
		# Update reticle appearance
		grapple_reticle.queue_redraw()

# Draw the grapple reticle
func _on_reticle_draw() -> void:
	if !grapple_reticle:
		return
	
	var color = Color.GREEN if grapple_target_valid else Color.RED
	var size = 10.0
	
	# Draw a simple crosshair
	grapple_reticle.draw_line(Vector2(-size, 0), Vector2(size, 0), color, 2.0)
	grapple_reticle.draw_line(Vector2(0, -size), Vector2(0, size), color, 2.0)
	
	# Draw a circle if target is valid
	if grapple_target_valid:
		grapple_reticle.draw_circle(Vector2.ZERO, size * 0.8, Color(color.r, color.g, color.b, 0.3))
		
		# Draw distance indicator if we're hitting something
		var raycast = cam.get_node("GrappleRaycast") as RayCast3D
		if raycast and raycast.is_colliding():
			var hit_point = raycast.get_collision_point()
			var distance = cam.global_position.distance_to(hit_point)
			var distance_text = str(int(distance)) + "m"
			
			# Draw distance text below reticle
			grapple_reticle.draw_string(
				ThemeDB.fallback_font, 
				Vector2(-20, size * 2), 
				distance_text, 
				HORIZONTAL_ALIGNMENT_CENTER, 
				-1, 
				14, 
				color
			)

func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "attack":
		anim_player.play("idle")
		hitbox.monitoring = false

func _on_hitbox_area_entered(area: Area3D) -> void:
	if area.is_in_group("enemy"):
		print("enemy hit")
