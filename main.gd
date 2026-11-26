extends Node3D

const MODEL = preload("res://assets/survivor_rig.glb")
const PROFILE = preload("res://assets/jump_profiles.gd")
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
var jump_phase := 0
var phase_clock := 0.0
var jump_length := 0.0
var jump_running := false
var jump_ground := 0.0
var jump_direction := Vector3.ZERO
var jump_speed := 0.0
var takeoff := 0.0
var touchdown := 0.0
var jump_height := 0.0
var prep_time := 0.16
var test_mode := false
var test_time := 0.0
var test_count := 0
var test_lift := 0.0
const WALK_SPEED := 1.614
const RUN_SPEED := 4.23
const SIDE_WALK_SPEED := 1.67
const SIDE_RUN_SPEED := 4.37
const RUN_JUMP_SPEED := 4.612
const PACK_STATES := ["pack_idle", "pack_walk", "pack_run", "pack_jump", "pack_left_walk", "pack_right_walk", "pack_left_run", "pack_right_run", "pack_left_90", "pack_right_90", "pack_left_180", "pack_right_180"]
const LOOP_STATES := ["idle", "walk", "run", "pack_idle", "pack_walk", "pack_run", "pack_left_walk", "pack_right_walk", "pack_left_run", "pack_right_run"]
var turning := false
var turn_clock := 0.0
var turn_length := 0.0
var turn_angle := 0.0
var turn_start := 0.0
var reverse_gait := false
var queued_turn := 0.0
var test_seen: Dictionary = {}
var last_gait := "pack_idle"
const RUN_JUMP_SPEED := 4.612
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
	body.floor_max_angle = deg_to_rad(46.0)
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
		anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
		for key in anim.get_animation_list():
			var name_lower := String(key).to_lower()
			for state in ["idle", "walk", "run", "jump", "run_jump"] + PACK_STATES:
				if name_lower == state or name_lower.ends_with("/" + state):
					clips[state] = key
					if state in LOOP_STATES:
						anim.get_animation(key).loop_mode = Animation.LOOP_LINEAR
		_play("pack_idle", 0.0)
	if clips.size() != 17:
		push_error("Animation import incomplete: " + str(clips))
		get_tree().quit(1)
		return
	var expected := {"idle": 14.3333333, "walk": 1.0333333, "run": 0.6, "jump": 2.3666667, "run_jump": 0.9333333, "pack_idle": 8.2, "pack_walk": 1.0333333, "pack_run": 0.7, "pack_jump": 2.1666667, "pack_left_walk": 1.0333333, "pack_right_walk": 1.0333333, "pack_left_run": 0.6666667, "pack_right_run": 0.6666667, "pack_left_90": 0.9, "pack_right_90": 0.9333333, "pack_left_180": 1.6333333, "pack_right_180": 1.6333333}
	for state in expected:
		var duration: float = anim.get_animation(clips[state]).length
		if absf(duration - float(expected[state])) > 0.04:
			push_error("Unexpected clip duration: " + String(state) + " " + str(duration))
			get_tree().quit(1)
			return
	print("All 17 animation clips imported")
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

func _play(state: String, blend: float = 0.18, backwards: bool = false) -> void:
	if anim == null or not clips.has(state):
		return
	if current == state and reverse_gait == backwards:
		return
	var old := current
	var phase := 0.0
	var sync_cycle := old in LOOP_STATES and state in LOOP_STATES and old != "pack_idle" and state != "pack_idle" and old != "idle" and state != "idle"
	if sync_cycle and anim.current_animation_length > 0.0:
		phase = fposmod(anim.current_animation_position / anim.current_animation_length, 1.0)
	current = state
	reverse_gait = backwards
	test_seen[state] = true
	anim.speed_scale = 1.0
	anim.play(clips[state], blend, -1.0 if backwards else 1.0, backwards)
	if sync_cycle:
		anim.seek(phase * anim.get_animation(clips[state]).length, false)

func _start_jump(horizontal: Vector3) -> void:
	jump_running = horizontal.length() > 2.8
	jump_direction = horizontal.normalized() if jump_running else Vector3.ZERO
	jump_speed = horizontal.length() if jump_running else 0.0
	jump_ground = body.position.y
	phase_clock = 0.0
	jump_phase = 1
	var state := "run_jump" if jump_running else "pack_jump"
	_play(state, 0.10)
	jump_length = anim.get_animation(clips[state]).length
	var meta: Array = PROFILE.JUMPS[state]
	takeoff = float(meta[0])
	touchdown = float(meta[1])
	jump_height = clampf(float(meta[2]), 0.24, 0.65)
	prep_time = minf(0.16, takeoff)
	if takeoff > prep_time:
		anim.seek(takeoff - prep_time, true)

func _launch() -> void:
	jump_phase = 2
	phase_clock = 0.0
	body.floor_snap_length = 0.0
	body.velocity.y = sqrt(2.0 * gravity * jump_height)
	var flight := 2.0 * body.velocity.y / gravity
	anim.seek(takeoff, true)
	anim.speed_scale = maxf(touchdown - takeoff, 0.05) / flight

func _land() -> void:
	jump_phase = 3
	phase_clock = 0.0
	body.floor_snap_length = 0.20
	anim.seek(touchdown, true)
	anim.speed_scale = maxf(jump_length - touchdown, 0.04) / 0.24
	test_count += 1

func _reset_player() -> void:
	body.position = Vector3(0, 0.05, 0)
	body.velocity = Vector3.ZERO
	visual.position.y = 0.0
	body.floor_snap_length = 0.20
	jump_phase = 0
	phase_clock = 0.0
	turning = false
	queued_turn = 0.0
	last_gait = "pack_idle"
	visual.rotation.y = yaw + PI
	_play("pack_idle", 0.1)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and captured:
		yaw -= event.relative.x * 0.003
		pitch = clampf(pitch - event.relative.y * 0.003, -0.65, 0.5)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			_toggle_menu()
		elif event.physical_keycode == KEY_R and captured:
			_reset_player()
		elif captured:
			match event.physical_keycode:
				KEY_Q: queued_turn = PI / 2.0
				KEY_E: queued_turn = -PI / 2.0
				KEY_Z: queued_turn = PI
				KEY_C: queued_turn = -PI

func _start_turn(angle: float) -> void:
	turning = true
	turn_clock = 0.0
	turn_start = visual.rotation.y
	var side := "left" if angle > 0.0 else "right"
	var degrees_name := "180" if absf(angle) > 2.0 else "90"
	_play("pack_" + side + "_" + degrees_name, 0.12)
	turn_length = anim.get_animation(clips[current]).length
	var curve: Array = PROFILE.TURNS[current]
	turn_angle = float(curve[curve.size() - 1])

func _turn_heading(time: float) -> float:
	var curve: Array = PROFILE.TURNS[current]
	var frame := clampf(time * 30.0, 0.0, float(curve.size() - 1))
	var i := int(floor(frame))
	return lerpf(float(curve[i]), float(curve[mini(i + 1, curve.size() - 1)]), frame - float(i))

func _finish_turn() -> void:
	turning = false
	visual.rotation.y = turn_start + turn_angle
	_play("pack_idle", 0.14)
	last_gait = "pack_idle"

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
		if test_time > 0.3 and test_time < 1.5: axis = Vector2(0, -1)
		elif test_time > 1.5 and test_time < 3.5: axis = Vector2(0, -1)
		elif test_time > 4.0 and test_time < 5.3: axis = Vector2(-1, 0)
		elif test_time > 5.5 and test_time < 6.8: axis = Vector2(1, 0)
		elif test_time > 7.1 and test_time < 8.3: axis = Vector2(-1, 0)
		elif test_time > 8.6 and test_time < 9.8: axis = Vector2(1, 0)
		sprint = (test_time > 1.5 and test_time < 3.5) or (test_time > 7.1 and test_time < 9.8)
		jump = (test_time > 2.3 and test_time < 2.4) or (test_time > 10.4 and test_time < 10.5)
		if test_time > 13.0 and test_time < 13.1 and not test_seen.has("pack_left_90"): queued_turn = PI / 2.0
		if test_time > 14.2 and test_time < 14.3 and not test_seen.has("pack_right_90"): queued_turn = -PI / 2.0
		if test_time > 15.6 and test_time < 15.7 and not test_seen.has("pack_left_180"): queued_turn = PI
		if test_time > 17.6 and test_time < 17.7 and not test_seen.has("pack_right_180"): queued_turn = -PI
		if test_time > 20.0:
			var missing: Array = []
			for state in PACK_STATES:
				if not test_seen.has(state): missing.append(state)
			if test_count == 2 and test_lift > 0.10 and missing.is_empty() and not turning:
				print("Locomotion smoke test OK: all 12 pack clips and both jumps")
				get_tree().quit()
			else:
				push_error("Locomotion smoke test failed: " + str(missing) + ", jumps " + str(test_count) + ", lift " + str(test_lift))
				get_tree().quit(1)
			return
	var pressed := jump and not jump_latch
	jump_latch = jump
	var input_dir := axis.normalized()
	var desired := Basis(Vector3.UP, yaw) * Vector3(input_dir.x, 0, input_dir.y)
	var horizontal := Vector3(body.velocity.x, 0, body.velocity.z)
	var grounded := body.is_on_floor()
	var lateral := absf(axis.x) > absf(axis.y) + 0.08
	var backwards := axis.y > 0.1 and not lateral
	var running := sprint and not backwards
	var nominal := (SIDE_RUN_SPEED if running else SIDE_WALK_SPEED) if lateral else (RUN_SPEED if running else WALK_SPEED)
	if backwards:
		nominal = WALK_SPEED * 0.82
	if turning:
		horizontal = Vector3.ZERO
		turn_clock = minf(turn_clock + delta, turn_length)
		visual.rotation.y = turn_start + _turn_heading(turn_clock)
		if turn_clock >= turn_length:
			_finish_turn()
	elif jump_phase == 0:
		var target := desired * nominal
		var accel := 10.0 if grounded else 2.2
		if desired.length_squared() < 0.01: accel = 14.0 if grounded else 0.8
		horizontal = horizontal.move_toward(target, accel * delta)
		if desired.length_squared() > 0.01:
			visual.rotation.y = lerp_angle(visual.rotation.y, yaw + PI, 1.0 - exp(-10.0 * delta))
			queued_turn = 0.0
		elif queued_turn != 0.0 and horizontal.length() < 0.15 and grounded:
			_start_turn(queued_turn)
			queued_turn = 0.0
			horizontal = Vector3.ZERO
		if pressed and grounded and not turning:
			if horizontal.length() > 2.8:
				visual.rotation.y = atan2(horizontal.x, horizontal.z)
			_start_jump(horizontal)
	if jump_phase == 1:
		phase_clock += delta
		horizontal = jump_direction * jump_speed if jump_running else horizontal.move_toward(Vector3.ZERO, 18.0 * delta)
		if phase_clock >= prep_time:
			_launch()
	elif jump_phase == 2:
		phase_clock += delta
		horizontal = horizontal.move_toward(desired * nominal, 1.2 * delta) if desired.length_squared() > 0.01 else horizontal
		if anim.current_animation_position > touchdown - 0.02:
			anim.seek(maxf(takeoff, touchdown - 0.02), true)
			anim.speed_scale = 0.0
	elif jump_phase == 3:
		phase_clock += delta
		horizontal = horizontal.move_toward(desired * nominal, 7.0 * delta)
		if phase_clock >= 0.24:
			jump_phase = 0
	if jump_phase == 2:
		if phase_clock > 0.0:
			body.velocity.y = maxf(body.velocity.y - gravity * delta, -35.0)
	elif grounded:
		body.velocity.y = -0.1
	else:
		body.velocity.y = maxf(body.velocity.y - gravity * delta, -35.0)
	body.velocity.x = horizontal.x
	body.velocity.z = horizontal.z
	body.move_and_slide()
	if jump_phase == 2:
		test_lift = maxf(test_lift, body.position.y - jump_ground)
		if body.is_on_floor() and body.velocity.y <= 0.0 and phase_clock > 0.08:
			_land()
	if jump_phase == 0 and not turning:
		var local := Basis(Vector3.UP, yaw).inverse() * Vector3(body.get_real_velocity().x, 0, body.get_real_velocity().z)
		var speed := Vector2(local.x, local.z).length()
		if speed < 0.12:
			_play("pack_idle", 0.22)
			anim.speed_scale = 1.0
		else:
			var side_motion := absf(local.x) > absf(local.z) * 1.12
			if current in ["pack_left_walk", "pack_right_walk", "pack_left_run", "pack_right_run"]:
				side_motion = absf(local.x) > absf(local.z) * 0.85
			var fast := speed > (2.35 if current.ends_with("run") else 2.7)
			var gait := "pack_run" if fast else "pack_walk"
			var rate_base := RUN_SPEED if fast else WALK_SPEED
			var reverse := local.z > 0.12 and not side_motion
			if side_motion:
				gait = "pack_left_" if local.x < 0.0 else "pack_right_"
				gait += "run" if fast else "walk"
				rate_base = SIDE_RUN_SPEED if fast else SIDE_WALK_SPEED
			elif reverse:
				gait = "pack_walk"
				rate_base = WALK_SPEED
			_play(gait, 0.20, reverse)
			var target_rate := clampf(speed / rate_base, 0.18, 1.18)
			anim.speed_scale = lerpf(anim.speed_scale, target_rate, 1.0 - exp(-12.0 * delta))
	if body.position.y < -4.0:
		_reset_player()

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
	hint.text = "WASD  Mover / lateral     SHIFT  Correr     ESPAÇO  Pular     Q/E  Girar 90°     Z/C  Girar 180°     ESC  Menu"
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
