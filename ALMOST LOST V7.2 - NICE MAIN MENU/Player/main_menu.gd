extends Node3D

# Loading screen variables
var loading_style = 0  # 0 = CD spinning, 1 = corner logo, 2 = progress bar, 3 = loading text
var loading_progress = 0.0
var loading_cd_rotation = 0.0
var loading_dots = ""
var loading_dot_timer = 0.0

# Audio players
var music_player: AudioStreamPlayer
var sfx_player: AudioStreamPlayer

# Font variables
var custom_font: FontFile

# PSX shader material
var psx_material: ShaderMaterial

# Background animation variables
var time_passed = 0.0
var background_particles = []
var vignette_intensity = 0.0
var vignette_direction = 1

func _ready():
	# Load custom font if available
	load_custom_font()
	
	# Create PSX shader material
	create_psx_shader()
	
	# Create UI elements first before trying to access them
	create_ui_elements()
	
	# Then setup everything else
	setup_3d_background()
	setup_audio()
	start_background_animations()
	connect_signals()
	
	# Add CRT overlay effect
	add_crt_effect()
	
	# Start the background animation process
	set_process(true)
	
	
		# Direct connection to the quit button
	var quit_button = get_node_or_null("UI/MenuContainer/MainVBox/ButtonsContainer/QuitButtonContainer/QuitButton")
	if quit_button:
		print("Quit button found, connecting signal...")
		# Connect with a simple lambda function for direct quitting
		quit_button.pressed.connect(func(): 
			print("Quit button pressed, quitting game...")
			get_tree().quit()
		)
	else:
		print("ERROR: Quit button not found! Check the path.")
	
	

func _process(delta):
	# Update time for animations
	time_passed += delta
	
	# Animate background elements
	animate_background(delta)
	
	# Animate vignette effect
	animate_vignette(delta)
	
	# Update shader time parameters
	update_shader_time_parameters()

func update_shader_time_parameters():
	# Update time parameter in all shaders
	var crt_overlay = get_node_or_null("UI/CRTOverlay")
	if crt_overlay and crt_overlay.material:
		crt_overlay.material.set_shader_parameter("time", time_passed)
	
	# Update background model shader
	var background = get_node_or_null("MenuBackground/BackgroundModel")
	if background and background.material_override and background.material_override is ShaderMaterial:
		background.material_override.set_shader_parameter("time", time_passed)
	
	# Update any other shader materials
	for particle in background_particles:
		if is_instance_valid(particle) and particle.material_override and particle.material_override is ShaderMaterial:
			particle.material_override.set_shader_parameter("time", time_passed)

func animate_vignette(delta):
	# Pulsating vignette effect
	vignette_intensity += delta * 0.2 * vignette_direction
	if vignette_intensity > 0.4:
		vignette_intensity = 0.4
		vignette_direction = -1
	elif vignette_intensity < 0.2:
		vignette_intensity = 0.2
		vignette_direction = 1
		
	# Update vignette shader if it exists
	var crt_overlay = get_node_or_null("UI/CRTOverlay")
	if crt_overlay and crt_overlay.material:
		crt_overlay.material.set_shader_parameter("vignette_strength", vignette_intensity)

func animate_background(delta):
	# Animate background model
	var background = get_node_or_null("MenuBackground/BackgroundModel")
	if background:
		# Add a slight wobble to the background
		var wobble_x = sin(time_passed * 0.3) * 0.01
		var wobble_y = cos(time_passed * 0.2) * 0.01
		background.rotation.x = wobble_x
		background.rotation.z = wobble_y
		
		# Animate background material
		if background.material_override:
			var emission_pulse = (sin(time_passed * 0.5) * 0.1) + 0.3
			if background.material_override is StandardMaterial3D:
				background.material_override.emission_energy = emission_pulse
	
	# Animate floating cubes with more PSX-style jerky movement
	var menu_background = get_node_or_null("MenuBackground")
	if menu_background:
		for i in range(menu_background.get_child_count()):
			var child = menu_background.get_child(i)
			if child is MeshInstance3D and child.name != "BackgroundModel":
				# PSX-style jerky rotation - update rotation only at certain intervals
				if fmod(time_passed + i * 0.1, 0.2) < delta:
					# Snap rotation to 15-degree increments for PSX feel
					var snap_angle = PI / 12.0
					var target_x = round(sin(time_passed * 0.1 + i) * snap_angle) * snap_angle
					var target_y = round(cos(time_passed * 0.15 + i) * snap_angle) * snap_angle
					var target_z = round(sin(time_passed * 0.12 + i * 2) * snap_angle) * snap_angle
					
					child.rotation.x = lerp(child.rotation.x, target_x, 0.2)
					child.rotation.y = lerp(child.rotation.y, target_y, 0.2)
					child.rotation.z = lerp(child.rotation.z, target_z, 0.2)
				
				# Add color pulsing for some cubes
				if child.material_override and randf() < 0.01:  # Occasional color change
					if child.material_override is StandardMaterial3D:
						var color_pulse = (sin(time_passed + i) * 0.2) + 0.8
						child.material_override.albedo_color.r = clamp(child.material_override.albedo_color.r * color_pulse, 0, 1)
						
						if child.material_override.emission_enabled:
							child.material_override.emission_energy = (sin(time_passed * 0.7 + i) * 0.1) + 0.2

func load_custom_font():
	# Try to load a custom font if it exists
	if ResourceLoader.exists("res://assets/fonts/main_font.ttf"):
		custom_font = load("res://assets/fonts/main_font.ttf")
	else:
		print("Custom font not found. Using default font.")

func create_psx_shader():
	# Create a shader material for PSX-style rendering
	psx_material = ShaderMaterial.new()
	
	# Enhanced vertex snapping shader for PSX look with animated dithering
	var shader_code = """
	shader_type spatial;
	render_mode unshaded;
	
	uniform vec4 albedo : source_color = vec4(1.0);
	uniform float pixel_size = 4.0;
	uniform float dither_strength = 0.1;
	uniform float time = 0.0;
	
	void vertex() {
		// Snap vertex positions to grid (PSX style)
		VERTEX = round(VERTEX * 10.0) / 10.0;
	}
	
	void fragment() {
		// Apply animated dithering pattern (PSX style)
		float x_pattern = mod(FRAGCOORD.x + FRAGCOORD.y + time * 2.0, 2.0);
		float y_pattern = mod(FRAGCOORD.y - FRAGCOORD.x + time * 1.5, 2.0);
		float dither_pattern = mod(x_pattern + y_pattern, 2.0) * dither_strength;
		
		// Add subtle color shift based on time
		vec3 color_shift = vec3(
			sin(time * 0.1) * 0.03,
			cos(time * 0.15) * 0.03,
			sin(time * 0.2) * 0.03
		);
		
		ALBEDO = albedo.rgb + color_shift + vec3(dither_pattern);
	}
	"""
	
	var shader = Shader.new()
	shader.code = shader_code
	psx_material.shader = shader

# This is a partial code snippet to modify just the title area
# Replace the create_ui_elements function with this updated version

func create_ui_elements():
	# Create CanvasLayer for UI
	var ui = CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)
	
	# Create main menu container
	var menu_container = Control.new()
	menu_container.name = "MenuContainer"
	menu_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(menu_container)
	
	# Create a centered VBox for the entire menu
	var main_vbox = VBoxContainer.new()
	main_vbox.name = "MainVBox"
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 20)
	menu_container.add_child(main_vbox)
	
	# Add top spacer to push content down a bit
	var top_spacer = Control.new()
	top_spacer.name = "TopSpacer"
	top_spacer.custom_minimum_size = Vector2(0, 60)
	main_vbox.add_child(top_spacer)
	
	# Create title container with background
	var title_bg = Panel.new()
	title_bg.name = "TitleBackground"
	title_bg.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	title_bg.custom_minimum_size = Vector2(600, 150)
	
	# Add PSX-style background for title
	var title_bg_style = StyleBoxFlat.new()
	title_bg_style.bg_color = Color(0.2, 0.2, 0.3, 0.7)
	title_bg_style.border_width_left = 2
	title_bg_style.border_width_top = 2
	title_bg_style.border_width_right = 2
	title_bg_style.border_width_bottom = 2
	title_bg_style.border_color = Color(0.7, 0.0, 0.0)
	title_bg.add_theme_stylebox_override("panel", title_bg_style)
	
	main_vbox.add_child(title_bg)
	
	# Create a CenterContainer to ensure proper centering both horizontally and vertically
	var center_container = CenterContainer.new()
	center_container.name = "TitleCenterContainer"
	center_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_bg.add_child(center_container)
	
	# Create a Control node to hold both title and shadow
	var title_holder = Control.new()
	title_holder.name = "TitleHolder"
	title_holder.custom_minimum_size = Vector2(400, 80) # Set a minimum size for proper centering
	# Add a slight offset to the right to fix the centering issue
	title_holder.position.x = 10 # This helps center it better
	center_container.add_child(title_holder)
	
	# Create game title with shadow effect (PSX style)
	var title_shadow = Label.new()
	title_shadow.name = "GameTitleShadow"
	title_shadow.text = "BLOODRUSH"
	title_shadow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_shadow.add_theme_font_size_override("font_size", 72)
	title_shadow.add_theme_color_override("font_color", Color(0.3, 0.0, 0.0))
	title_shadow.position = Vector2(3, 3)  # Offset for shadow
	title_shadow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Apply custom font if loaded
	if custom_font:
		title_shadow.add_theme_font_override("font", custom_font)

	title_holder.add_child(title_shadow)
	
	# Create game title (on top of shadow)
	var game_title = Label.new()
	game_title.name = "GameTitle"
	game_title.text = "BLOODRUSH"
	game_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_title.add_theme_font_size_override("font_size", 72)
	game_title.add_theme_color_override("font_color", Color(1.0, 0.0, 0.0))
	game_title.position = Vector2(0, 0)  # Position on top of shadow
	game_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Apply custom font if loaded
	if custom_font:
		game_title.add_theme_font_override("font", custom_font)

	title_holder.add_child(game_title)
	
	# Add enhanced blood drips to the title
	add_enhanced_blood_drips(title_holder)
	
	# Add extra spacing before subtitle
	var subtitle_spacer = Control.new()
	subtitle_spacer.name = "SubtitleSpacer"
	subtitle_spacer.custom_minimum_size = Vector2(0, 20) # Add more space before subtitle
	main_vbox.add_child(subtitle_spacer)
	
	# Add subtitle underneath the title box
	var subtitle = Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = "EXTREME CARNAGE"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 24)
	subtitle.add_theme_color_override("font_color", Color(0.8, 0.0, 0.0))
	subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Apply custom font if loaded
	if custom_font:
		subtitle.add_theme_font_override("font", custom_font)
	
	main_vbox.add_child(subtitle)
	
	# Add spacer between subtitle and buttons
	var mid_spacer = Control.new()
	mid_spacer.name = "MidSpacer"
	mid_spacer.custom_minimum_size = Vector2(0, 40)
	main_vbox.add_child(mid_spacer)
	
	# Create buttons container (centered)
	var buttons_container = VBoxContainer.new()
	buttons_container.name = "ButtonsContainer"
	buttons_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons_container.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons_container.add_theme_constant_override("separation", 20)
	main_vbox.add_child(buttons_container)
	
	# Create PSX-style buttons (centered)
	create_psx_button(buttons_container, "StartButton", "START GAME")
	create_psx_button(buttons_container, "OptionsButton", "OPTIONS")
	create_psx_button(buttons_container, "QuitButton", "QUIT")
	
	# Add bottom spacer to push everything up a bit
	var bottom_spacer = Control.new()
	bottom_spacer.name = "BottomSpacer"
	bottom_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(bottom_spacer)
	
	# Create copyright text (PSX games often had this)
	var copyright = Label.new()
	copyright.name = "CopyrightText"
	copyright.text = "© 2025 LIME INTERACTIVE"
	copyright.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	copyright.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	copyright.add_theme_font_size_override("font_size", 12)
	copyright.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))  # Brighter text
	copyright.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	copyright.position.y = -30
	menu_container.add_child(copyright)
	
	# Create version label with PSX style
	var version_label = Label.new()
	version_label.name = "VersionLabel"
	version_label.text = "v1.0"  # PSX games often had simple version numbers
	version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	version_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	version_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	version_label.position = Vector2(-20, -20)
	version_label.add_theme_font_size_override("font_size", 16)
	version_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))  # Brighter text
	menu_container.add_child(version_label)
	
	# Create options menu (hidden initially)
	create_options_menu(ui)
	
	# Add animated title effect
	animate_title(game_title, title_shadow, subtitle)
	


func animate_title(game_title, title_shadow, subtitle):
	# Add pulsating glow to the title
	var title_tween = create_tween()
	title_tween.set_loops()
	
	# Pulse the title color
	title_tween.tween_property(game_title, "theme_override_colors/font_color", Color(0.9, 0.1, 0.1), 1.5)
	title_tween.tween_property(game_title, "theme_override_colors/font_color", Color(0.7, 0.0, 0.0), 1.5)
	
	# Animate shadow with slight delay
	var shadow_tween = create_tween()
	shadow_tween.set_loops()
	shadow_tween.tween_interval(0.2) # Slight delay
	shadow_tween.tween_property(title_shadow, "theme_override_colors/font_color", Color(0.3, 0.0, 0.0), 1.5)
	shadow_tween.tween_property(title_shadow, "theme_override_colors/font_color", Color(0.15, 0.0, 0.0), 1.5)
	
	# Animate subtitle with slight delay
	var subtitle_tween = create_tween()
	subtitle_tween.set_loops()
	subtitle_tween.tween_interval(0.3) # Slight delay
	subtitle_tween.tween_property(subtitle, "theme_override_colors/font_color", Color(0.7, 0.1, 0.1), 1.5)
	subtitle_tween.tween_property(subtitle, "theme_override_colors/font_color", Color(0.5, 0.0, 0.0), 1.5)
	
	# Add PSX-style jitter to the title (occasional)
	var jitter_tween = create_tween()
	jitter_tween.set_loops()
	
	# Wait random intervals then apply jitter
	jitter_tween.tween_interval(randf_range(3.0, 7.0))
	jitter_tween.tween_callback(func(): apply_title_jitter(game_title, title_shadow))
	jitter_tween.tween_interval(0.1)
	jitter_tween.tween_callback(func(): reset_title_position(game_title, title_shadow))

func apply_title_jitter(title, shadow):
	# Apply random jitter to simulate PSX instability
	var jitter_x = randf_range(-2.0, 2.0)
	var jitter_y = randf_range(-1.0, 1.0)
	
	title.position = Vector2(jitter_x, jitter_y)
	shadow.position = Vector2(3 + jitter_x, 3 + jitter_y)

func reset_title_position(title, shadow):
	# Reset positions
	title.position = Vector2(0, 0)
	shadow.position = Vector2(3, 3)

func create_psx_button(parent, button_name, button_text):
	# Create a container for the button (without decoration)
	var button_container = HBoxContainer.new()
	button_container.name = button_name + "Container"
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	button_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(button_container)
	
	# Create the button with enhanced PSX style
	var button = Button.new()
	button.name = button_name
	button.text = button_text
	button.custom_minimum_size = Vector2(300, 40)  # Wider buttons for PSX style
	
	# Apply custom font if loaded
	if custom_font:
		button.add_theme_font_override("font", custom_font)
	else:
		# If no custom font, make text uppercase for PSX feel
		button.text = button_text.to_upper()
	
	# Add enhanced PSX-style to the button
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.15, 0.15, 0.2)
	normal_style.border_width_left = 2
	normal_style.border_width_top = 2
	normal_style.border_width_right = 2
	normal_style.border_width_bottom = 2
	normal_style.border_color = Color(0.3, 0.3, 0.4)
	normal_style.shadow_color = Color(0, 0, 0, 0.3)
	normal_style.shadow_size = 2
	normal_style.shadow_offset = Vector2(2, 2)
	
	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = Color(0.25, 0.25, 0.3)
	hover_style.border_width_left = 2
	hover_style.border_width_top = 2
	hover_style.border_width_right = 2
	hover_style.border_width_bottom = 2
	hover_style.border_color = Color(0.7, 0.0, 0.0)  # Red border for PSX feel
	hover_style.shadow_color = Color(0, 0, 0, 0.4)
	hover_style.shadow_size = 3
	hover_style.shadow_offset = Vector2(2, 2)
	
	var pressed_style = StyleBoxFlat.new()
	pressed_style.bg_color = Color(0.1, 0.1, 0.15)
	pressed_style.border_width_left = 2
	pressed_style.border_width_top = 2
	pressed_style.border_width_right = 2
	pressed_style.border_width_bottom = 2
	pressed_style.border_color = Color(0.5, 0.0, 0.0)
	pressed_style.shadow_color = Color(0, 0, 0, 0.2)
	pressed_style.shadow_size = 1
	pressed_style.shadow_offset = Vector2(1, 1)
	
	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", pressed_style)
	
	button_container.add_child(button)
	
	# Add the button to its container
	button_container.add_child(button)
	
	# Add direct functionality for the quit button
	if button_name == "QuitButton":
		print("Setting up quit button functionality...")
		button.pressed.connect(func():
			print("Quit button pressed!")
			# Try multiple quit methods
			print("Attempting to quit with get_tree().quit()...")
			get_tree().quit()
			
			
		)

func animate_button_decoration(deco_label):
	# Create a pulsating animation for the button decoration
	var tween = create_tween()
	tween.set_loops()
	
	# Pulse the decoration
	tween.tween_property(deco_label, "position:x", -5.0, 0.8)
	tween.tween_property(deco_label, "position:x", 0.0, 0.8)

func create_options_menu(ui):
	# Create options menu (hidden initially)
	var options_menu = Control.new()
	options_menu.name = "OptionsMenu"
	options_menu.visible = false
	options_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(options_menu)
	
	# Create a semi-transparent background
	var bg_overlay = ColorRect.new()
	bg_overlay.name = "BackgroundOverlay"
	bg_overlay.color = Color(0, 0, 0, 0.7)
	bg_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	options_menu.add_child(bg_overlay)
	
	# Create options panel with PSX style
	var options_panel = Panel.new()
	options_panel.name = "OptionsPanel"
	options_panel.set_anchors_preset(Control.PRESET_CENTER)
	options_panel.custom_minimum_size = Vector2(500, 400)
	
	# Add PSX panel style
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.1, 0.15)
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.6, 0.0, 0.0)  # Red border for PSX feel
	panel_style.shadow_color = Color(0, 0, 0, 0.5)
	panel_style.shadow_size = 4
	panel_style.shadow_offset = Vector2(4, 4)
	options_panel.add_theme_stylebox_override("panel", panel_style)
	
	options_menu.add_child(options_panel)
	
	# Create options container
	var options_container = VBoxContainer.new()
	options_container.name = "OptionsContainer"
	options_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	options_container.add_theme_constant_override("separation", 20)
	options_container.add_theme_constant_override("margin_top", 20)
	options_container.add_theme_constant_override("margin_left", 20)
	options_container.add_theme_constant_override("margin_right", 20)
	options_container.add_theme_constant_override("margin_bottom", 20)
	options_panel.add_child(options_container)
	
	# Add options title with PSX style and shadow
	var options_title_shadow = Label.new()
	options_title_shadow.name = "OptionsTitleShadow"
	options_title_shadow.text = "OPTIONS"
	options_title_shadow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	options_title_shadow.add_theme_font_size_override("font_size", 32)
	options_title_shadow.add_theme_color_override("font_color", Color(0.2, 0.0, 0.0))  # Shadow color
	options_title_shadow.position = Vector2(2, 2)  # Offset for shadow
	
	# Apply custom font if loaded
	if custom_font:
		options_title_shadow.add_theme_font_override("font", custom_font)
	
	options_container.add_child(options_title_shadow)
	
	var options_title = Label.new()
	options_title.name = "OptionsTitle"
	options_title.text = "OPTIONS"
	options_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	options_title.add_theme_font_size_override("font_size", 32)
	options_title.add_theme_color_override("font_color", Color(0.8, 0.0, 0.0))  # Red for PSX feel
	options_title.position = Vector2(0, 0)  # Position on top of shadow
	
	# Apply custom font if loaded
	if custom_font:
		options_title.add_theme_font_override("font", custom_font)
	
	options_container.add_child(options_title)
	
	# Add simple PSX-style options (no tabs, just simple options)
	var settings_container = VBoxContainer.new()
	settings_container.name = "SettingsContainer"
	settings_container.add_theme_constant_override("separation", 15)
	settings_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	options_container.add_child(settings_container)
	
	# Add fullscreen toggle
	var fullscreen_container = HBoxContainer.new()
	fullscreen_container.name = "FullscreenContainer"
	settings_container.add_child(fullscreen_container)
	
	var fullscreen_label = Label.new()
	fullscreen_label.text = "FULLSCREEN"
	fullscreen_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fullscreen_container.add_child(fullscreen_label)
	
	var fullscreen_toggle = CheckButton.new()
	fullscreen_toggle.name = "FullscreenToggle"
	fullscreen_container.add_child(fullscreen_toggle)
	
	# Add music volume slider
	var music_container = HBoxContainer.new()
	music_container.name = "MusicContainer"
	settings_container.add_child(music_container)
	
	var music_label = Label.new()
	music_label.text = "MUSIC VOLUME"
	music_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	music_container.add_child(music_label)
	
	var music_slider = HSlider.new()
	music_slider.name = "MusicVolumeSlider"
	music_slider.min_value = 0
	music_slider.max_value = 1
	music_slider.step = 0.1
	music_slider.value = 0.8
	music_slider.custom_minimum_size = Vector2(150, 20)
	music_container.add_child(music_slider)
	
	# Add SFX volume slider
	var sfx_container = HBoxContainer.new()
	sfx_container.name = "SFXContainer"
	settings_container.add_child(sfx_container)
	
	var sfx_label = Label.new()
	sfx_label.text = "SFX VOLUME"
	sfx_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sfx_container.add_child(sfx_label)
	
	var sfx_slider = HSlider.new()
	sfx_slider.name = "SFXVolumeSlider"
	sfx_slider.min_value = 0
	sfx_slider.max_value = 1
	sfx_slider.step = 0.1
	sfx_slider.value = 0.8
	sfx_slider.custom_minimum_size = Vector2(150, 20)
	sfx_container.add_child(sfx_slider)
	
	# Add resolution option (PSX had limited resolutions)
	var resolution_container = HBoxContainer.new()
	resolution_container.name = "ResolutionContainer"
	settings_container.add_child(resolution_container)
	
	var resolution_label = Label.new()
	resolution_label.text = "RESOLUTION"
	resolution_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resolution_container.add_child(resolution_label)
	
	var resolution_option = OptionButton.new()
	resolution_option.name = "ResolutionOption"
	resolution_option.add_item("320x240", 0)  # PSX resolution
	resolution_option.add_item("640x480", 1)
	resolution_option.add_item("800x600", 2)
	resolution_option.selected = 0  # Default to PSX resolution
	resolution_container.add_child(resolution_option)
	
	# Add dithering option (PSX effect)
	var dither_container = HBoxContainer.new()
	dither_container.name = "DitherContainer"
	settings_container.add_child(dither_container)
	
	var dither_label = Label.new()
	dither_label.text = "DITHERING"
	dither_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dither_container.add_child(dither_label)
	
	var dither_toggle = CheckButton.new()
	dither_toggle.name = "DitherToggle"
	dither_toggle.button_pressed = true
	dither_container.add_child(dither_toggle)
	
	# Add CRT effect option
	var crt_container = HBoxContainer.new()
	crt_container.name = "CRTContainer"
	settings_container.add_child(crt_container)
	
	var crt_label = Label.new()
	crt_label.text = "CRT EFFECT"
	crt_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crt_container.add_child(crt_label)
	
	var crt_toggle = CheckButton.new()
	crt_toggle.name = "CRTToggle"
	crt_toggle.button_pressed = true
	crt_container.add_child(crt_toggle)
	
	# Add buttons container at the bottom
	var buttons_container = HBoxContainer.new()
	buttons_container.name = "OptionsButtonsContainer"
	buttons_container.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons_container.add_theme_constant_override("separation", 20)
	options_container.add_child(buttons_container)
	
	# Add back button with PSX style
	var back_button = Button.new()
	back_button.name = "BackButton"
	back_button.text = "BACK"
	back_button.custom_minimum_size = Vector2(150, 40)
	
	# Apply custom font if loaded
	if custom_font:
		back_button.add_theme_font_override("font", custom_font)
	
	# Add PSX-style to the button
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.15, 0.15, 0.2)
	normal_style.border_width_left = 2
	normal_style.border_width_top = 2
	normal_style.border_width_right = 2
	normal_style.border_width_bottom = 2
	normal_style.border_color = Color(0.3, 0.3, 0.4)
	normal_style.shadow_color = Color(0, 0, 0, 0.3)
	normal_style.shadow_size = 2
	normal_style.shadow_offset = Vector2(2, 2)
	
	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = Color(0.25, 0.25, 0.3)
	hover_style.border_width_left = 2
	hover_style.border_width_top = 2
	hover_style.border_width_right = 2
	hover_style.border_width_bottom = 2
	hover_style.border_color = Color(0.7, 0.0, 0.0)
	hover_style.shadow_color = Color(0, 0, 0, 0.4)
	hover_style.shadow_size = 3
	hover_style.shadow_offset = Vector2(2, 2)
	
	var pressed_style = StyleBoxFlat.new()
	pressed_style.bg_color = Color(0.1, 0.1, 0.15)
	pressed_style.border_width_left = 2
	pressed_style.border_width_top = 2
	pressed_style.border_width_right = 2
	pressed_style.border_width_bottom = 2
	pressed_style.border_color = Color(0.5, 0.0, 0.0)
	pressed_style.shadow_color = Color(0, 0, 0, 0.2)
	pressed_style.shadow_size = 1
	pressed_style.shadow_offset = Vector2(1, 1)
	
	back_button.add_theme_stylebox_override("normal", normal_style)
	back_button.add_theme_stylebox_override("hover", hover_style)
	back_button.add_theme_stylebox_override("pressed", pressed_style)
	
	buttons_container.add_child(back_button)

func setup_3d_background():
	# Check if MenuBackground exists, if not create it
	var menu_background
	if has_node("MenuBackground"):
		menu_background = get_node("MenuBackground")
	else:
		menu_background = Node3D.new()
		menu_background.name = "MenuBackground"
		add_child(menu_background)
	
	# Check if BackgroundModel exists, if not create it
	var background_model
	if menu_background.has_node("BackgroundModel"):
		background_model = menu_background.get_node("BackgroundModel")
	else:
		background_model = MeshInstance3D.new()
		background_model.name = "BackgroundModel"
		menu_background.add_child(background_model)
	
	# Now we can safely assign the mesh - use a low-poly sphere for PSX feel
	var mesh = SphereMesh.new()
	mesh.radius = 50
	mesh.height = 100
	mesh.is_hemisphere = true
	mesh.radial_segments = 12  # Low poly for PSX feel
	mesh.rings = 6  # Low poly for PSX feel
	background_model.mesh = mesh
	
	# Create an animated PSX-style material with shader - brighter
	var material = ShaderMaterial.new()
	var shader = Shader.new()
	
	# PSX-style background shader with animation - brighter colors
	shader.code = """
	shader_type spatial;
	render_mode unshaded;
	
	uniform float time = 0.0;
	
	void vertex() {
		// Snap vertex positions to grid (PSX style)
		VERTEX = round(VERTEX * 10.0) / 10.0;
		
		// Add subtle vertex animation
		VERTEX.y += sin(VERTEX.x * 0.1 + time * 0.2) * 0.5;
		VERTEX.x += cos(VERTEX.z * 0.1 + time * 0.15) * 0.5;
	}
	
	void fragment() {
		// Brighter base color
		vec3 base_color = vec3(0.3, 0.2, 0.4);
		
		// Add animated grid pattern
		float grid_size = 20.0;
		vec2 grid_uv = vec2(
			mod(FRAGCOORD.x / grid_size, 1.0),
			mod(FRAGCOORD.y / grid_size, 1.0)
		);
		
		// Create grid lines
		float grid_line_x = smoothstep(0.9, 1.0, grid_uv.x) + smoothstep(0.0, 0.1, grid_uv.x);
		float grid_line_y = smoothstep(0.9, 1.0, grid_uv.y) + smoothstep(0.0, 0.1, grid_uv.y);
		float grid_line = max(grid_line_x, grid_line_y);
		
		// Animate grid color - brighter
		vec3 grid_color = vec3(0.6, 0.2, 0.8) + vec3(sin(time * 0.2) * 0.1, 0.0, cos(time * 0.3) * 0.1);
		
		// Add pulsating glow
		float glow = 0.3 + 0.2 * sin(time * 0.5);
		
		// Final color
		vec3 final_color = mix(base_color, grid_color, grid_line * glow);
		
		// Add subtle noise
		final_color += vec3(fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453) * 0.03);
		
		ALBEDO = final_color;
		EMISSION = final_color * 0.7;  // Brighter emission
	}
	"""
	
	shader.code = shader.code.replace("FRAGCOORD", "FRAGCOORD")
	material.shader = shader
	background_model.material_override = material
	
	# Check if Camera3D exists, if not create it
	if !menu_background.has_node("Camera3D"):
		var camera = Camera3D.new()
		camera.name = "Camera3D"
		camera.current = true
		menu_background.add_child(camera)
	
	# Add animated background elements
	add_animated_background()

func add_animated_background():
	# Add animated background elements (PSX style)
	var parent = get_node("MenuBackground")
	
	# Add animated fog planes
	add_fog_planes(parent)
	
	# Add floating cubes with enhanced animation
	add_floating_cubes()
	
	# Add animated light sources
	add_animated_lights(parent)
	
	# Add particle system for floating bits
	add_particle_system(parent)

func add_particle_system(parent):
	# Create a simple particle system for floating bits (PSX style)
	var particles = GPUParticles3D.new()
	particles.name = "BackgroundParticles"
	particles.amount = 100
	particles.lifetime = 8.0
	particles.explosiveness = 0.0
	particles.randomness = 1.0
	particles.fixed_fps = 20  # Low FPS for PSX feel
	particles.local_coords = false
	particles.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	
	# Create particle material
	var particle_material = ParticleProcessMaterial.new()
	particle_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	particle_material.emission_sphere_radius = 20.0
	particle_material.direction = Vector3(0, 1, 0)
	particle_material.spread = 180.0
	particle_material.gravity = Vector3(0, -0.1, 0)
	particle_material.initial_velocity_min = 0.2
	particle_material.initial_velocity_max = 0.5
	particle_material.angular_velocity_min = 0.0
	particle_material.angular_velocity_max = 1.0
	particle_material.linear_accel_min = -0.1
	particle_material.linear_accel_max = 0.1
	particle_material.scale_min = 0.1
	particle_material.scale_max = 0.3
	
	# Set particle color
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(0.8, 0.0, 0.0, 0.5))
	gradient.add_point(0.5, Color(0.5, 0.0, 0.0, 0.3))
	gradient.add_point(1.0, Color(0.3, 0.0, 0.0, 0.0))
	
	var gradient_texture = GradientTexture1D.new()
	gradient_texture.gradient = gradient
	particle_material.color_ramp = gradient_texture
	
	particles.process_material = particle_material
	
	# Create mesh for particles (simple quad)
	var particle_mesh = QuadMesh.new()
	particle_mesh.size = Vector2(0.5, 0.5)
	
	# Create material for particles
	var mesh_material = StandardMaterial3D.new()
	mesh_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mesh_material.billboard_keep_scale = true
	mesh_material.albedo_color = Color(1.0, 0.2, 0.2, 0.8)
	mesh_material.emission_enabled = true
	mesh_material.emission = Color(0.8, 0.0, 0.0)
	mesh_material.emission_energy = 0.5
	
	particle_mesh.material = mesh_material
	particles.draw_pass_1 = particle_mesh
	
	parent.add_child(particles)
	particles.emitting = true

func add_fog_planes(parent):
	# Add fog planes for that classic PSX fog effect - brighter
	for i in range(5):
		var plane = MeshInstance3D.new()
		var mesh = PlaneMesh.new()
		mesh.size = Vector2(100, 100)
		plane.mesh = mesh
		
		# Create semi-transparent material for fog - brighter
		var material = StandardMaterial3D.new()
		material.albedo_color = Color(0.3, 0.2, 0.4, 0.1)  # Brighter purple
		material.emission_enabled = true
		material.emission = Color(0.2, 0.1, 0.3)  # Brighter emission
		material.emission_energy = 0.3  # More energy
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED  # Visible from both sides
		
		plane.material_override = material
		
		# Position at different depths
		var z_pos = -20.0 + (i * 8.0)
		plane.position = Vector3(0, 0, z_pos)
		plane.rotation.x = PI / 2  # Rotate to face camera
		
		parent.add_child(plane)
		
		# Store for animation
		background_particles.append(plane)
		
		# Add fog plane animation
		var tween = create_tween()
		tween.set_loops()
		tween.tween_property(plane, "position:y", plane.position.y + 5.0, 10.0 + i)
		tween.tween_property(plane, "position:y", plane.position.y, 10.0 + i)

func add_animated_lights(parent):
	# Add animated light sources for dynamic lighting - brighter
	for i in range(3):
		var light = OmniLight3D.new()
		light.name = "AnimatedLight" + str(i)
		
		# PSX-style colors - brighter
		var light_colors = [
			Color(1.0, 0.2, 0.2),  # Bright red
			Color(0.2, 0.2, 0.8),  # Bright blue
			Color(0.8, 0.2, 0.8)   # Bright purple
		]
		
		light.light_color = light_colors[i % light_colors.size()]
		light.light_energy = 0.8  # Higher energy for brighter scene
		light.omni_range = 20.0  # Larger range
		
		# Position around the scene
		var angle = i * (2.0 * PI / 3.0)
		var radius = 15.0
		light.position = Vector3(cos(angle) * radius, sin(angle) * radius, -5)
		
		parent.add_child(light)
		
		# Create animation for the light
		var tween = create_tween()
		tween.set_loops()
		
		# Animate light intensity
		tween.tween_property(light, "light_energy", 0.4, 2.0)
		tween.tween_property(light, "light_energy", 0.8, 2.0)
		
		# Animate light position slightly
		var pos_tween = create_tween()
		pos_tween.set_loops()
		pos_tween.tween_property(light, "position:y", light.position.y + 2.0, 3.0)
		pos_tween.tween_property(light, "position:y", light.position.y - 2.0, 3.0)

func add_floating_cubes():
	# Add some floating cubes to the background (PSX style)
	var parent = get_node("MenuBackground")
	
	# Create 30 random floating cubes with enhanced animation
	for i in range(30):
		var cube = MeshInstance3D.new()
		var mesh = BoxMesh.new()
		
		# Use simple cube sizes for PSX feel
		mesh.size = Vector3(1, 1, 1) * randf_range(0.5, 2.0)
		cube.mesh = mesh
		
		# Create PSX-style materials
		var material = StandardMaterial3D.new()
		
		# Use a PSX-style color palette
		var color_palette = [
			Color(0.7, 0.0, 0.0),  # Dark red
			Color(0.5, 0.0, 0.0),  # Darker red
			Color(0.3, 0.0, 0.0),  # Very dark red
			Color(0.2, 0.2, 0.3),  # Dark blue-gray
			Color(0.1, 0.1, 0.2)   # Very dark blue
		]
		
		material.albedo_color = color_palette[randi() % color_palette.size()]
		material.metallic = 0.0  # No metallic for PSX
		material.roughness = 1.0  # Full roughness for PSX
		
		# Simple emission for PSX feel
		if randf() > 0.5:  # Only some cubes emit light
			material.emission_enabled = true
			material.emission = material.albedo_color
			material.emission_energy = randf_range(0.1, 0.3)  # Low energy for PSX feel
		
		cube.material_override = material
		
		# Position randomly in a sphere
		var radius = randf_range(15.0, 25.0)
		var angle1 = randf() * 2.0 * PI
		var angle2 = randf() * 2.0 * PI
		var x = radius * sin(angle1) * cos(angle2)
		var y = radius * sin(angle1) * sin(angle2)
		var z = radius * cos(angle1)
		
		# Snap positions to grid for PSX feel
		x = round(x)
		y = round(y)
		z = round(z)
		
		cube.position = Vector3(x, y, z)
		parent.add_child(cube)
		
		# Add enhanced floating animation with PSX-style jerky movement
		var float_duration = randf_range(3.0, 6.0)
		var float_distance = randf_range(1.0, 2.0)
		
		# Round the float distance to whole units for PSX feel
		float_distance = round(float_distance)
		
		var tween = create_tween()
		tween.set_loops()
		
		# Add random delay for more varied movement
		if randf() > 0.5:
			tween.tween_interval(randf_range(0.0, 1.0))
			
		tween.tween_property(cube, "position:y", cube.position.y + float_distance, float_duration)
		tween.tween_property(cube, "position:y", cube.position.y, float_duration)
		
		# Store for additional animation in _process
		background_particles.append(cube)

func add_crt_effect():
	# Add a CRT effect overlay with enhanced animation
	var ui = get_node_or_null("UI")
	if ui:
		var crt_overlay = ColorRect.new()
		crt_overlay.name = "CRTOverlay"
		crt_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		crt_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Don't block mouse input
		ui.add_child(crt_overlay)
		
		# Create a shader material for enhanced CRT effect with animation
		var shader_material = ShaderMaterial.new()
		var shader = Shader.new()
		
		# Enhanced CRT shader with animation - brighter
		shader.code = """
		shader_type canvas_item;
		
		uniform float scan_line_count : hint_range(0, 1080) = 240.0;
		uniform float brightness : hint_range(0.0, 2.0) = 1.4;  // Increased brightness
		uniform float vignette_strength : hint_range(0.0, 1.0) = 0.2;  // Reduced vignette
		uniform float time : hint_range(0.0, 1000.0) = 0.0;
		uniform float noise_strength : hint_range(0.0, 0.1) = 0.015;  // Reduced noise
		
		// Random function
		float random(vec2 uv) {
			return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453123);
		}
		
		void fragment() {
			// Get base color
			vec4 color = texture(TEXTURE, UV);
			
			// Animated scan lines - less intense
			float scan_line = sin((UV.y + time * 0.1) * scan_line_count * 3.14159);
			color.rgb *= 0.9 + 0.1 * scan_line;  // Less scan line effect
			
			// Apply brightness
			color.rgb *= brightness;
			
			// Apply animated vignette - less intense
			float vignette_size = 0.7 + 0.1 * sin(time * 0.2);  // Larger vignette size
			float vignette = UV.x * (1.0 - UV.x) * UV.y * (1.0 - UV.y) * vignette_size;
			vignette = clamp(pow(16.0 * vignette, vignette_strength), 0.0, 1.0);
			color.rgb *= vignette;
			
			// Add subtle noise (PSX video noise) - reduced
			float noise = random(UV + vec2(time * 0.01, 0.0)) * noise_strength;
			color.rgb += vec3(noise);
			
			// Add subtle color distortion (RGB shift) - reduced
			float shift_amount = 0.0005 + 0.0003 * sin(time * 0.5);
			vec4 color_r = texture(TEXTURE, UV + vec2(shift_amount, 0.0));
			vec4 color_b = texture(TEXTURE, UV - vec2(shift_amount, 0.0));
			color.r = mix(color.r, color_r.r, 0.15);
			color.b = mix(color.b, color_b.b, 0.15);
			
			// Add horizontal distortion lines (occasional) - reduced
			float distortion_chance = step(0.998, fract(time * 0.1 + UV.y * 10.0));
			float distortion_offset = (random(vec2(time, UV.y)) * 2.0 - 1.0) * 0.005 * distortion_chance;
			vec4 distorted_color = texture(TEXTURE, vec2(UV.x + distortion_offset, UV.y));
			color = mix(color, distorted_color, distortion_chance * 0.3);
			
			COLOR = color;
		}
		"""
		
		shader_material.shader = shader
		crt_overlay.material = shader_material

func setup_audio():
	# Create music player
	music_player = AudioStreamPlayer.new()
	add_child(music_player)
	
	# Create SFX player
	sfx_player = AudioStreamPlayer.new()
	add_child(sfx_player)
	
	# Add sound to all buttons
	var buttons_container = get_node_or_null("UI/MenuLayout/ButtonsContainer")
	if buttons_container:
		for button_container in buttons_container.get_children():
			var button = button_container.get_node_or_null(button_container.name.replace("Container", ""))
			if button:
				button.mouse_entered.connect(func(): button_hover_effect(button, true))
				button.mouse_exited.connect(func(): button_hover_effect(button, false))

func button_hover_effect(button, is_hovering):
	var tween = create_tween()
	if is_hovering:
		# PSX-style hover effect (simpler)
		tween.tween_property(button, "modulate", Color(1.0, 0.7, 0.7), 0.1)
		
		# Get the left decoration
		var container = button.get_parent()
		var left_deco = container.get_node_or_null("LeftDeco")
		if left_deco:
			var deco_tween = create_tween()
			deco_tween.tween_property(left_deco, "modulate", Color(1.0, 0.5, 0.5), 0.1)
		
		# Play hover sound if available
		if sfx_player and ResourceLoader.exists("res://assets/audio/button_hover.wav"):
			sfx_player.stream = load("res://assets/audio/button_hover.wav")
			sfx_player.play()
	else:
		# Reset to normal
		tween.tween_property(button, "modulate", Color(1, 1, 1), 0.1)
		
		# Reset the left decoration
		var container = button.get_parent()
		var left_deco = container.get_node_or_null("LeftDeco")
		if left_deco:
			var deco_tween = create_tween()
			deco_tween.tween_property(left_deco, "modulate", Color(1, 1, 1), 0.1)

func start_background_animations():
	# Update shader parameters in process function instead
	pass

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		# Clean up any resources
		for particle in background_particles:
			if is_instance_valid(particle):
				particle.queue_free()

func connect_signals():
	# Connect button signals
	var start_button = get_node_or_null("UI/MenuContainer/MainVBox/ButtonsContainer/StartButtonContainer/StartButton")
	var options_button = get_node_or_null("UI/MenuContainer/MainVBox/ButtonsContainer/OptionsButtonContainer/OptionsButton")
	var quit_button = get_node_or_null("UI/MenuContainer/MainVBox/ButtonsContainer/QuitButtonContainer/QuitButton")
	
	if start_button:
		start_button.pressed.connect(start_game)
	if options_button:
		options_button.pressed.connect(show_options)
	if quit_button:
		quit_button.pressed.connect(quit_game)
	
	
	# Connect options menu signals
	var back_button = get_node_or_null("UI/OptionsMenu/OptionsPanel/OptionsContainer/OptionsButtonsContainer/BackButton")
	
	if back_button:
		back_button.pressed.connect(hide_options)
	
	# Connect options controls
	var fullscreen_toggle = get_node_or_null("UI/OptionsMenu/OptionsPanel/OptionsContainer/SettingsContainer/FullscreenContainer/FullscreenToggle")
	var music_slider = get_node_or_null("UI/OptionsMenu/OptionsPanel/OptionsContainer/SettingsContainer/MusicContainer/MusicVolumeSlider")
	var sfx_slider = get_node_or_null("UI/OptionsMenu/OptionsPanel/OptionsContainer/SettingsContainer/SFXContainer/SFXVolumeSlider")
	var crt_toggle = get_node_or_null("UI/OptionsMenu/OptionsPanel/OptionsContainer/SettingsContainer/CRTContainer/CRTToggle")
	
	if fullscreen_toggle:
		fullscreen_toggle.toggled.connect(toggle_fullscreen)
	if music_slider:
		music_slider.value_changed.connect(set_music_volume)
	if sfx_slider:
		sfx_slider.value_changed.connect(set_sfx_volume)
	if crt_toggle:
		crt_toggle.toggled.connect(toggle_crt_effect)

func start_game():
	# Play select sound
	if sfx_player and ResourceLoader.exists("res://assets/audio/button_select.wav"):
		sfx_player.stream = load("res://assets/audio/button_select.wav")
		sfx_player.play()
	
	# PSX-style loading screen
	show_psx_loading_screen()
	
	# Wait a moment before changing scene (simulating PSX loading)
	await get_tree().create_timer(2.0).timeout
	
	# Change scene
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func show_psx_loading_screen():
	# Create a PS1-style loading screen
	var ui = get_node_or_null("UI")
	if ui:
		# Create loading screen container
		var loading_screen = ColorRect.new()
		loading_screen.name = "LoadingScreen"
		loading_screen.color = Color(0, 0, 0)
		loading_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
		ui.add_child(loading_screen)
		
		
		# Add loading text
		var loading_text = Label.new()
		loading_text.text = "LOADING..."
		loading_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		loading_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		loading_text.set_anchors_preset(Control.PRESET_CENTER)
		loading_text.add_theme_font_size_override("font_size", 32)
		loading_text.add_theme_color_override("font_color", Color(0.8, 0.0, 0.0))
		
		# Apply custom font if loaded
		if custom_font:
			loading_text.add_theme_font_override("font", custom_font)
		
		loading_screen.add_child(loading_text)
		
		# Animate the loading text
		var tween = create_tween()
		tween.set_loops()
		tween.tween_property(loading_text, "modulate:a", 0.2, 0.5)
		tween.tween_property(loading_text, "modulate:a", 1.0, 0.5)

func show_options():
	# Show options menu
	var options_menu = get_node_or_null("UI/OptionsMenu")
	if options_menu:
		# Play select sound
		if sfx_player and ResourceLoader.exists("res://assets/audio/button_select.wav"):
			sfx_player.stream = load("res://assets/audio/button_select.wav")
			sfx_player.play()
		
		options_menu.visible = true
		
		# Simple fade-in for PSX feel
		options_menu.modulate = Color(1, 1, 1, 0)
		var tween = create_tween()
		tween.tween_property(options_menu, "modulate", Color(1, 1, 1, 1), 0.2)

func hide_options():
	var options_menu = get_node_or_null("UI/OptionsMenu")
	if options_menu:
		# Play select sound
		if sfx_player and ResourceLoader.exists("res://assets/audio/button_select.wav"):
			sfx_player.stream = load("res://assets/audio/button_select.wav")
			sfx_player.play()
		
		# Simple fade-out for PSX feel
		var tween = create_tween()
		tween.tween_property(options_menu, "modulate", Color(1, 1, 1, 0), 0.2)
		tween.tween_callback(func(): options_menu.visible = false)

func quit_game():
	# Play select sound if available

	
	# Create a CRT turn-off effect
	var ui = get_node_or_null("UI")
	if ui:
		# Create a white flash
		var flash_rect = ColorRect.new()
		flash_rect.name = "FlashRect"
		flash_rect.color = Color(1, 1, 1, 0)  # Start transparent
		flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ui.add_child(flash_rect)
		
		# Create a black fade rect
		var fade_rect = ColorRect.new()
		fade_rect.name = "FadeRect"
		fade_rect.color = Color(0, 0, 0, 0)  # Start transparent
		fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ui.add_child(fade_rect)
		
		# Create CRT line effect
		var line_rect = ColorRect.new()
		line_rect.name = "LineRect"
		line_rect.color = Color(1, 1, 1, 0)  # Start transparent
		line_rect.size = Vector2(1280, 2)  # Adjust width based on your resolution
		line_rect.position = Vector2(0, 360)  # Center of screen
		line_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ui.add_child(line_rect)
		
		# Create turn-off animation
		var tween = create_tween()
		
		# Flash white briefly
		tween.tween_property(flash_rect, "color:a", 0.4, 0.1)
		tween.tween_property(flash_rect, "color:a", 0.0, 0.1)
		
		# Show horizontal line
		tween.parallel().tween_property(line_rect, "color:a", 1.0, 0.1)
		
		# Shrink screen to horizontal line
		tween.tween_callback(func():
			var screen_tween = create_tween()
			
			# Shrink all UI elements to center
			for child in ui.get_children():
				if child != line_rect and child != flash_rect and child != fade_rect:
					var original_pos = child.position
					var original_size = child.size
					
					screen_tween.parallel().tween_property(child, "position:y", 360, 0.3)
					screen_tween.parallel().tween_property(child, "scale:y", 0.001, 0.3)
		)
		
		# Wait a moment
		tween.tween_interval(0.3)
		
		# Fade out the line
		tween.tween_property(line_rect, "color:a", 0.0, 0.2)
		
		# Fade to black
		tween.parallel().tween_property(fade_rect, "color:a", 1.0, 0.3)
		
		# Quit after animation completes
		tween.tween_callback(func(): get_tree().quit())
	else:
		# Just quit if UI doesn't exist
		get_tree().quit()

func toggle_fullscreen(enabled):
	if enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func set_music_volume(value):
	if music_player:
		music_player.volume_db = linear_to_db(value)

func set_sfx_volume(value):
	if sfx_player:
		sfx_player.volume_db = linear_to_db(value)

func toggle_crt_effect(enabled):
	var crt_overlay = get_node_or_null("UI/CRTOverlay")
	if crt_overlay:
		crt_overlay.visible = enabled


func add_enhanced_blood_drips(parent_node):
	# Create blood drips for the title with enhanced effects
	# We'll create several drips at different positions
	var drip_positions = [
		Vector2(50, 0),   # B
		Vector2(100, 0),  # L
		Vector2(150, 0),  # O
		Vector2(200, 0),  # O
		Vector2(250, 0),  # D
		Vector2(300, 0),  # R
		Vector2(350, 0),  # U
		Vector2(75, 0),   # Extra drip
		Vector2(175, 0),  # Extra drip
		Vector2(275, 0)   # Extra drip
	]
	
	# Create a container for all blood effects
	var blood_container = Control.new()
	blood_container.name = "BloodEffects"
	blood_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent_node.add_child(blood_container)
	
	for i in range(drip_positions.size()):
		var pos = drip_positions[i]
		
		# Create a blood drip with more complex shape
		var drip = create_blood_drip(pos, i)
		blood_container.add_child(drip)
		
		# Animate the drip
		animate_enhanced_blood_drip(drip)
		
		# Add blood pool at the bottom for some drips
		if randf() > 0.6:
			var pool = create_blood_pool(pos, i)
			blood_container.add_child(pool)
			animate_blood_pool(pool)
	
	# Add occasional blood splatter
	for i in range(3):
		var splatter = create_blood_splatter(Vector2(randf_range(50, 350), randf_range(20, 60)), i)
		blood_container.add_child(splatter)

func create_blood_drip(pos, index):
	# Create a more complex blood drip using a Control node with multiple parts
	var drip_container = Control.new()
	drip_container.name = "BloodDrip" + str(index)
	drip_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Randomize position with more variation
	drip_container.position = Vector2(pos.x + randf_range(-20, 20), 70 + randf_range(-5, 5))
	
	# Main drip body
	var main_drip = ColorRect.new()
	main_drip.name = "MainDrip"
	main_drip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Randomize drip width and height
	var drip_width = randf_range(4, 10)
	var drip_height = randf_range(20, 50)
	
	main_drip.size = Vector2(drip_width, drip_height)
	
	# Use a darker, more realistic blood color with slight transparency
	main_drip.color = Color(0.6, 0.0, 0.0, 0.9)
	
	drip_container.add_child(main_drip)
	
	# Add a highlight to make it look more 3D
	var highlight = ColorRect.new()
	highlight.name = "Highlight"
	highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	highlight.size = Vector2(max(1, drip_width * 0.3), drip_height)
	highlight.color = Color(0.8, 0.1, 0.1, 0.7)
	drip_container.add_child(highlight)
	
	# Add a drip head (the rounded part at the bottom)
	var drip_head = ColorRect.new()
	drip_head.name = "DripHead"
	drip_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drip_head.size = Vector2(drip_width + 4, drip_width + 4)
	drip_head.color = Color(0.6, 0.0, 0.0, 0.9)
	drip_head.position = Vector2(-2, drip_height - 2)
	drip_container.add_child(drip_head)
	
	# Add small side drips for some
	if randf() > 0.7:
		var side_drip = ColorRect.new()
		side_drip.name = "SideDrip"
		side_drip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		side_drip.size = Vector2(randf_range(2, 4), randf_range(5, 15))
		side_drip.color = Color(0.6, 0.0, 0.0, 0.9)
		
		# Position either left or right of main drip
		var side_pos_x = randf() > 0.5 if drip_width else -side_drip.size.x
		var side_pos_y = randf_range(5, drip_height * 0.7)
		side_drip.position = Vector2(side_pos_x, side_pos_y)
		
		drip_container.add_child(side_drip)

	
	return drip_container

func create_blood_pool(pos, index):
	# Create a blood pool that forms at the bottom of some drips
	var pool = Control.new()
	pool.name = "BloodPool" + str(index)
	pool.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Position at the bottom of where a drip would be
	pool.position = Vector2(pos.x + randf_range(-20, 20), 120 + randf_range(0, 10))
	
	# Create the main pool shape
	var pool_shape = ColorRect.new()
	pool_shape.name = "PoolShape"
	pool_shape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pool_shape.size = Vector2(randf_range(8, 15), randf_range(3, 6))
	pool_shape.color = Color(0.5, 0.0, 0.0, 0.0) # Start invisible
	pool.add_child(pool_shape)
	
	return pool

func create_blood_splatter(pos, index):
	# Create a blood splatter effect
	var splatter = Control.new()
	splatter.name = "BloodSplatter" + str(index)
	splatter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	splatter.position = pos
	
	# Create multiple small dots for the splatter
	for i in range(randi_range(3, 8)):
		var dot = ColorRect.new()
		dot.name = "SplatterDot" + str(i)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.size = Vector2(randf_range(1, 3), randf_range(1, 3))
		dot.color = Color(0.7, 0.0, 0.0, randf_range(0.6, 0.9))
		
		# Random position around the center
		var angle = randf() * 2 * PI
		var distance = randf_range(2, 10)
		dot.position = Vector2(cos(angle) * distance, sin(angle) * distance)
		
		splatter.add_child(dot)
	
	return splatter

func animate_enhanced_blood_drip(drip):
	# Get the main drip and drip head
	var main_drip = drip.get_node("MainDrip")
	var highlight = drip.get_node("Highlight")
	var drip_head = drip.get_node("DripHead")
	
	# Initial growth animation
	var initial_tween = create_tween()
	var growth_time = randf_range(2.0, 5.0)
	var target_height = main_drip.size.y + randf_range(20, 40)
	
	initial_tween.tween_property(main_drip, "size:y", target_height, growth_time)
	initial_tween.parallel().tween_property(highlight, "size:y", target_height, growth_time)
	initial_tween.parallel().tween_property(drip_head, "position:y", target_height - 2, growth_time)
	
	# Create looping animation for continuous dripping effect
	var loop_tween = create_tween()
	loop_tween.set_loops()
	
	# Random delay before next drip
	loop_tween.tween_interval(randf_range(4.0, 10.0))
	
	# Reset drip size with a callback
	loop_tween.tween_callback(func():
		var reset_tween = create_tween()
		var new_height = randf_range(10, 25)
		
		# Animate the transition to make it smoother
		reset_tween.tween_property(main_drip, "size:y", new_height, 0.3)
		reset_tween.parallel().tween_property(highlight, "size:y", new_height, 0.3)
		reset_tween.parallel().tween_property(drip_head, "position:y", new_height - 2, 0.3)
		
		# Create a falling blood drop
		if randf() > 0.3:
			create_falling_drop(drip)
	)
	
	# Grow drip again
	loop_tween.tween_callback(func():
		var grow_tween = create_tween()
		var new_target = randf_range(30, 70)
		var new_time = randf_range(3.0, 6.0)
		
		grow_tween.tween_property(main_drip, "size:y", new_target, new_time)
		grow_tween.parallel().tween_property(highlight, "size:y", new_target, new_time)
		grow_tween.parallel().tween_property(drip_head, "position:y", new_target - 2, new_time)
	)
	
	# Animate any side drips if they exist
	var side_drip = drip.get_node_or_null("SideDrip")
	if side_drip:
		var side_tween = create_tween()
		side_tween.tween_property(side_drip, "size:y", side_drip.size.y + randf_range(5, 15), randf_range(1.0, 3.0))

func create_falling_drop(drip):
	# Create a falling blood drop effect
	var main_drip = drip.get_node("MainDrip")
	var drip_head = drip.get_node("DripHead")
	
	# Create a new drop that looks like the drip head
	var drop = ColorRect.new()
	drop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drop.size = drip_head.size
	drop.color = drip_head.color
	drop.position = Vector2(drip_head.position.x, drip_head.position.y)
	
	# Add to the same parent
	drip.get_parent().add_child(drop)
	
	# Animate the falling drop
	var fall_tween = create_tween()
	
	# Fall down
	fall_tween.tween_property(drop, "position:y", drop.position.y + randf_range(80, 120), randf_range(0.8, 1.5))
	
	# Fade out as it falls
	fall_tween.parallel().tween_property(drop, "modulate:a", 0.0, randf_range(0.6, 1.0))

	# Remove the drop when done
	fall_tween.tween_callback(drop.queue_free)

func animate_blood_pool(pool):
	var pool_shape = pool.get_node("PoolShape")
	
	# Start invisible and grow over time
	var pool_tween = create_tween()
	
	# Fade in
	pool_tween.tween_property(pool_shape, "color:a", 0.8, randf_range(0.5, 1.0))
	
	# Grow width
	pool_tween.parallel().tween_property(pool_shape, "size:x", pool_shape.size.x * randf_range(2.0, 4.0), randf_range(3.0, 6.0))
	
	# Grow height slightly
	pool_tween.parallel().tween_property(pool_shape, "size:y", pool_shape.size.y * randf_range(1.2, 1.8), randf_range(3.0, 6.0))

func animate_blood_drip(drip):
	# Create initial drip animation (growing downward)
	var initial_tween = create_tween()
	initial_tween.tween_property(drip, "size:y", drip.size.y + randf_range(10, 30), randf_range(1.0, 3.0))
	
	# Create looping animation for continuous dripping effect
	var loop_tween = create_tween()
	loop_tween.set_loops()
	
	# Random delay before next drip
	loop_tween.tween_interval(randf_range(3.0, 8.0))
	
	# Reset drip size
	loop_tween.tween_callback(func():
		drip.size.y = randf_range(5, 15)
	)
	
	# Grow drip
	loop_tween.tween_property(drip, "size:y", randf_range(30, 60), randf_range(2.0, 4.0))
	
	# Occasionally make the drip fall off
	if randf() > 0.7:
		loop_tween.tween_callback(func():
			var fall_tween = create_tween()
			# Clone the drip for the falling effect
			var falling_drip = ColorRect.new()
			falling_drip.color = drip.color
			falling_drip.size = drip.size
			falling_drip.position = drip.position
			drip.get_parent().add_child(falling_drip)
			
			# Animate the falling drip
			fall_tween.parallel().tween_property(falling_drip, "position:y", falling_drip.position.y + 100, 1.0)
			fall_tween.parallel().tween_property(falling_drip, "modulate:a", 0.0, 1.0)
			fall_tween.tween_callback(falling_drip.queue_free)
			
			# Reset original drip
			drip.size.y = randf_range(5, 10)
		)
