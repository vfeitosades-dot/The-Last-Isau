extends Node3D

const MODEL = preload("res://assets/survivor_rig.glb")
var body: CharacterBody3D
var visual: Node3D
var anim: AnimationPlayer
var pivot: Node3D
var camera: Camera3D
var status: Label
var overlay: PanelContainer
var yaw := 0.0
var pitch := -0.13
var jump_latch := false
var jump_phase := 0 # 0: ground, 1: anticipation, 2: flight, 3: recovery
var jump_clock := 0.0
var jump_buffer := 0.0
var jump_running := false
var walk_speed := 1.62
var run_speed := 5.05
var lift_speed := 2.55
var prep_duration := 0.18
var recovery_duration := 0.26
var launch_frame := 0.46
var land_frame := 0.96
var jump_length := 1.41
var flight_time := 0.52
var test_mode := false
var test_time := 0.0
var test_started := false
var test_landed := false
var clips: Dictionary = {}
var current := ""
var captured := true
var gravity := 9.81

func _ready() -> void:
	var world := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("657a92")
	sky_material.sky_horizon_color = Color("b7c0c5")
	sky_material.ground_bottom_color = Color("424747")
	sky_material.ground_horizon_color = Color("b7c0c5")
	sky.sky_material = sky_material
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("c6c6c6")
	e.ambient_light_energy = 0.65
	world.environment = e
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -38, 0)
	sun.light_color = Color("f5f5f5")
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	_make_floor()
	body = CharacterBody3D.new()
	body.name = "Player"
	body.position = Vector3(0, 0.025, 0)
	body.floor_snap_length = 0.20
	body.floor_stop_on_slope = true
	body.safe_margin = 0.005
	add_child(body)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.8
	var collider := CollisionShape3D.new()
	collider.shape = capsule
	collider.position.y = 0.9
	body.add_child(collider)
	visual = Node3D.new()
	visual.rotation.y = PI
	body.add_child(visual)
	var model := MODEL.instantiate() as Node3D
	visual.add_child(model)
	anim = _find_anim(model)
	if anim != null:
		for key in anim.get_animation_list():
			var name_lower := String(key).to_lower()
			for state in ["idle", "walk", "run", "jump", "run_jump"]:
				if name_lower == state or name_lower.ends_with("/" + state):
					clips[state] = key
					if state in ["idle", "walk", "run"]:
						anim.get_animation(key).loop_mode = Animation.LOOP_LINEAR
		_play("idle", 0.0)
	if clips.size() != 5:
		push_error("Animation import incomplete: " + str(clips))
		get_tree().quit(1)
		return
	print("All 5 animation clips imported")
	test_mode = "--motion-test" in OS.get_cmdline_user_args()
	pivot = Node3D.new()
	add_child(pivot)
	camera = Camera3D.new()
	camera.position = Vector3(0.65, 0.25, 3.75)
	camera.rotation_degrees = Vector3(-6, 0, 0)
	camera.fov = 70.0
	camera.near = 0.08
	camera.current = true
	pivot.add_child(camera)
	pivot.position = body.position + Vector3(0, 1.35, 0)
	_build_ui()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _make_floor() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.position.y = -0.25
	add_child(floor_body)
	var shape := BoxShape3D.new()
	shape.size = Vector3(160, 0.5, 160)
	var col := CollisionShape3D.new()
	col.shape = shape
	floor_body.add_child(col)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = shape.size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("737775")
	mat.roughness = 0.92
	mesh.material_override = mat
	floor_body.add_child(mesh)
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color("626765")
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES, line_mat)
	for i in range(-80, 81, 2):
		im.surface_add_vertex(Vector3(i, 0.006, -80))
		im.surface_add_vertex(Vector3(i, 0.006, 80))
		im.surface_add_vertex(Vector3(-80, 0.006, i))
		im.surface_add_vertex(Vector3(80, 0.006, i))
	im.surface_end()
	var grid := MeshInstance3D.new()
	grid.mesh = im
	grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(grid)

func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for child in n.get_children():
		var found := _find_anim(child)
		if found != null:
			return found
	return null

func _play(state: String, blend: float = 0.18) -> void:
	if anim == null or not clips.has(state) or current == state:
		return
	var old := current
	var phase := 0.0
	if old in ["walk", "run"] and state in ["walk", "run"] and anim.current_animation_length > 0.0:
		phase = fposmod(anim.current_animation_position / anim.current_animation_length, 1.0)
	current = state
	anim.play(clips[state], blend)
	if phase > 0.0:
		anim.seek(phase * anim.get_animation(clips[state]).length, false)

func _start_jump(speed: float) -> void:
	jump_running = speed > 2.7
	prep_duration = 0.065 if jump_running else 0.19
	recovery_duration = 0.16 if jump_running else 0.26
	launch_frame = 0.075 if jump_running else 0.46
	land_frame = 0.66 if jump_running else 0.96
	lift_speed = 2.95 if jump_running else 2.55
	flight_time = 2.0 * lift_speed / gravity
	_play("run_jump" if jump_running else "jump", 0.075)
	jump_length = anim.get_animation(clips[current]).length
	anim.speed_scale = launch_frame / prep_duration
	jump_clock = 0.0
	jump_phase = 1

func _launch() -> void:
	jump_phase = 2
	jump_clock = 0.0
	anim.seek(launch_frame, true)
	anim.speed_scale = (land_frame - launch_frame) / flight_time
	body.velocity.y = lift_speed
	test_started = true

func _land() -> void:
	jump_phase = 3
	jump_clock = 0.0
	anim.seek(land_frame, true)
	anim.speed_scale = maxf(jump_length - land_frame, 0.02) / recovery_duration
	test_landed = true

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and captured:
		yaw -= event.relative.x * 0.003
		pitch = clampf(pitch - event.relative.y * 0.003, -0.65, 0.5)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			_toggle_menu()
		elif event.physical_keycode == KEY_R and captured:
			body.position = Vector3(0, 0.05, 0)
			body.velocity = Vector3.ZERO
			jump_phase = 0
			jump_buffer = 0.0

func _physics_process(delta: float) -> void:
	if body == null or pivot == null:
		return
	var axis := Vector2.ZERO
	if captured:
		axis.x = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
		axis.y = float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	var sprint := captured and Input.is_physical_key_pressed(KEY_SHIFT)
	var jump := captured and Input.is_physical_key_pressed(KEY_SPACE)
	if test_mode:
		test_time += delta
		axis = Vector2(0, -1) if test_time > 0.2 and test_time < 3.2 else Vector2.ZERO
		sprint = test_time > 0.6 and test_time < 3.2
		jump = test_time > 1.6 and test_time < 1.7
		if test_time > 3.8:
			if test_started and test_landed:
				print("Motion smoke test OK: jump and landing")
				get_tree().quit()
			else:
				push_error("Motion smoke test failed")
				get_tree().quit(1)
			return
	if jump and not jump_latch:
		jump_buffer = 0.14
	jump_latch = jump
	jump_buffer = maxf(jump_buffer - delta, 0.0)
	axis = axis.normalized()
	var desired := Basis(Vector3.UP, yaw) * Vector3(axis.x, 0, axis.y)
	var horizontal := Vector3(body.velocity.x, 0, body.velocity.z)
	var grounded := body.is_on_floor()
	var target := desired * (run_speed if sprint else walk_speed)
	# Weight transfer and inertia: no instantaneous stop on a direction change.
	var acceleration := 9.0 if grounded else 2.1
	if axis.length_squared() < 0.01:
		acceleration = 12.0 if grounded else 0.65
	if jump_phase == 1 and not jump_running:
		target *= 0.2
	if jump_phase == 3:
		target *= 0.82
	horizontal = horizontal.move_toward(target, acceleration * delta)
	body.velocity.x = horizontal.x
	body.velocity.z = horizontal.z
	var speed := horizontal.length()
	if speed > 0.18:
		var target_yaw := atan2(horizontal.x, horizontal.z)
		visual.rotation.y = lerp_angle(visual.rotation.y, target_yaw, 1.0 - exp(-(10.5 if grounded else 3.0) * delta))
	elif desired.length_squared() > 0.01 and jump_phase == 0:
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(desired.x, desired.z), 1.0 - exp(-9.0 * delta))
	if grounded:
		if body.velocity.y < 0.0:
			body.velocity.y = 0.0
	else:
		body.velocity.y = maxf(body.velocity.y - gravity * delta, -35.0)
	if jump_phase == 0 and grounded and jump_buffer > 0.0:
		jump_buffer = 0.0
		_start_jump(speed)
	if jump_phase == 1:
		jump_clock += delta
		if jump_clock >= prep_duration and grounded:
			_launch()
		elif not grounded:
			jump_phase = 0
	elif jump_phase == 2:
		jump_clock += delta
		# Hold the final airborne pose if falling from a higher surface.
		if anim.current_animation_position >= land_frame - 0.015:
			anim.seek(land_frame - 0.015, true)
			anim.speed_scale = 0.0
	elif jump_phase == 3:
		jump_clock += delta
		if jump_clock >= recovery_duration:
			jump_phase = 0
	body.move_and_slide()
	if jump_phase == 2 and body.is_on_floor() and body.velocity.y <= 0.0 and jump_clock > 0.08:
		_land()
	if jump_phase == 0:
		var actual := Vector2(body.get_real_velocity().x, body.get_real_velocity().z).length()
		if not body.is_on_floor():
			_play("jump", 0.13)
			anim.speed_scale = 0.0
			anim.seek(0.70, true)
		elif actual < 0.15:
			_play("idle", 0.22)
			anim.speed_scale = lerpf(anim.speed_scale, 1.0, 1.0 - exp(-12.0 * delta))
		else:
			var use_run := actual > (2.35 if current == "run" else 2.85)
			_play("run" if use_run else "walk", 0.18)
			var nominal := run_speed if use_run else walk_speed
			var rate := clampf(actual / nominal, 0.38, 1.55)
			anim.speed_scale = lerpf(anim.speed_scale, rate, 1.0 - exp(-14.0 * delta))
	if body.position.y < -4.0:
		body.position = Vector3(0, 0.05, 0)
		body.velocity = Vector3.ZERO
		jump_phase = 0
		jump_buffer = 0.0

func _process(delta: float) -> void:
	if pivot == null:
		return
	pivot.position = pivot.position.lerp(body.position + Vector3(0, 1.35, 0), 1.0 - exp(-9.0 * delta))
	pivot.rotation = Vector3(pitch, yaw, 0)
	status.text = "THE LAST ISAU  /  %s  /  %d FPS" % [current.to_upper() if not current.is_empty() else "SEM CLIP", Engine.get_frames_per_second()]

func _toggle_menu() -> void:
	captured = not captured
	overlay.visible = not captured
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE

func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var margin := MarginContainer.new()
	margin.position = Vector2(20, 16)
	ui.add_child(margin)
	var labels := VBoxContainer.new()
	margin.add_child(labels)
	status = Label.new()
	status.add_theme_font_size_override("font_size", 18)
	labels.add_child(status)
	var hint := Label.new()
	hint.text = "WASD  Mover     SHIFT  Correr     ESPAÇO  Pular     Mouse  Câmera     R  Reset     ESC  Menu"
	hint.add_theme_font_size_override("font_size", 13)
	labels.add_child(hint)
	overlay = PanelContainer.new()
	overlay.position = Vector2(400, 235)
	overlay.custom_minimum_size = Vector2(480, 220)
	ui.add_child(overlay)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	overlay.add_child(box)
	var title := Label.new()
	title.text = "THE LAST ISAU / PAUSA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var resume := Button.new()
	resume.text = "Continuar"
	resume.pressed.connect(_toggle_menu)
	box.add_child(resume)
	var quit := Button.new()
	quit.text = "Sair"
	quit.pressed.connect(func(): get_tree().quit())
	box.add_child(quit)
	overlay.hide()
