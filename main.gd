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
var jumping := false
var jump_clock := 0.0
var jump_length := 0.0
var jump_running := false
var jump_ground := 0.0
var jump_direction := Vector3.ZERO
var test_mode := false
var test_time := 0.0
var test_started := false
var test_landed := false
var test_count := 0
var test_lift := 0.0
const WALK_SPEED := 1.614
const RUN_SPEED := 4.23
const SIDE_WALK_SPEED := 1.67
const SIDE_RUN_SPEED := 4.37
const PACK_STATES := ["pack_idle", "pack_walk", "pack_run", "pack_jump", "pack_left_walk", "pack_right_walk", "pack_left_run", "pack_right_run", "pack_left_90", "pack_right_90", "pack_left_180", "pack_right_180"]
const LOOP_STATES := ["idle", "walk", "run", "pack_idle", "pack_walk", "pack_run", "pack_left_walk", "pack_right_walk", "pack_left_run", "pack_right_run"]
var turning := false
var turn_clock := 0.0
var turn_length := 0.0
var turn_angle := 0.0
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

func _play(state: String, blend: float = 0.15) -> void:
	if anim == null or not clips.has(state) or current == state:
		return
	current = state
	test_seen[state] = true
	anim.speed_scale = 1.0
	anim.play(clips[state], blend)

func _start_jump(horizontal: Vector3) -> void:
	jump_running = horizontal.length() > 2.8
	jump_direction = horizontal.normalized() if jump_running else Vector3.ZERO
	jump_ground = body.position.y
	jump_clock = 0.0
	jumping = true
	body.floor_snap_length = 0.0
	_play("run_jump" if jump_running else "pack_jump", 0.10)
	jump_length = anim.get_animation(clips[current]).length
	test_started = true

func _jump_height(time: float) -> float:
	var values: Array = PROFILE.RUN_JUMP if jump_running else PROFILE.PACK_JUMP
	var frame := clampf(time * 30.0, 0.0, float(values.size() - 1))
	var i := int(floor(frame))
	var j := mini(i + 1, values.size() - 1)
	return lerpf(float(values[i]), float(values[j]), frame - float(i))

func _reset_player() -> void:
	body.position = Vector3(0, 0.05, 0)
	body.velocity = Vector3.ZERO
	visual.position.y = 0.0
	body.floor_snap_length = 0.20
	jumping = false
	jump_clock = 0.0
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
	turn_angle = angle
	var side := "left" if angle > 0.0 else "right"
	var degrees_name := "180" if absf(angle) > 2.0 else "90"
	_play("pack_" + side + "_" + degrees_name, 0.10)
	turn_length = anim.get_animation(clips[current]).length
	# Root yaw in the FBX carries the visible turn. Commit base yaw once, at clip end.

func _finish_turn() -> void:
	turning = false
	visual.rotation.y += turn_angle
	# Do not blend an already-rotated pelvis with a newly-rotated visual root.
	_play("pack_idle", 0.0)
	anim.advance(0.0)
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
	var lateral := absf(axis.x) > absf(axis.y)
	var gait := "pack_run" if sprint else "pack_walk"
	var nominal := RUN_SPEED if sprint else WALK_SPEED
	if lateral:
		gait = "pack_left_" if axis.x < 0.0 else "pack_right_"
		gait += "run" if sprint else "walk"
		nominal = SIDE_RUN_SPEED if sprint else SIDE_WALK_SPEED
	if turning:
		horizontal = Vector3.ZERO
		turn_clock += delta
		if turn_clock >= turn_length:
			_finish_turn()
	elif not jumping:
		var target := desired * nominal
		horizontal = horizontal.move_toward(target, (16.0 if desired.length_squared() > 0.01 else 20.0) * delta)
		if desired.length_squared() > 0.01:
			var target_yaw := yaw + PI if lateral else atan2(desired.x, desired.z)
			visual.rotation.y = lerp_angle(visual.rotation.y, target_yaw, 1.0 - exp(-12.0 * delta))
			last_gait = gait
			queued_turn = 0.0
		elif queued_turn != 0.0 and horizontal.length() < 0.15 and body.is_on_floor():
			_start_turn(queued_turn)
			queued_turn = 0.0
			horizontal = Vector3.ZERO
		if pressed and body.is_on_floor() and not turning:
			if horizontal.length() > 2.8:
				visual.rotation.y = atan2(horizontal.x, horizontal.z)
			_start_jump(horizontal)
	if jumping:
		jump_clock = minf(jump_clock + delta, jump_length)
		horizontal = jump_direction * RUN_JUMP_SPEED if jump_running else Vector3.ZERO
		var height := _jump_height(jump_clock)
		test_lift = maxf(test_lift, height)
		var target_y := jump_ground + height
		body.velocity.y = (target_y - body.position.y) / delta
		if height <= 0.001 and body.velocity.y <= 0.01:
			body.velocity.y = minf(body.velocity.y, -0.12)
	else:
		body.velocity.y = maxf(body.velocity.y - gravity * delta, -35.0) if not body.is_on_floor() else -0.1
	body.velocity.x = horizontal.x
	body.velocity.z = horizontal.z
	body.move_and_slide()
	if jumping:
		visual.position.y = jump_ground - body.position.y
		if jump_clock >= jump_length - 0.001:
			jumping = false
			body.floor_snap_length = 0.20
			test_landed = true
			test_count += 1
	elif not turning:
		visual.position.y = move_toward(visual.position.y, 0.0, delta * 2.0)
		var speed := Vector2(body.velocity.x, body.velocity.z).length()
		if speed < 0.12:
			_play("pack_idle", 0.15)
		else:
			_play(last_gait, 0.15)
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
