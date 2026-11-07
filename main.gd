extends Node3D
## Этап 0: проверка сборки. Мир, персонаж, камера, виртуальный стик, прыжок.

const WALK := 5.5
const RUN := 9.0
const GRAVITY := 24.0
const JUMP_V := 8.5
const STICK_R := 90.0

var player: CharacterBody3D
var model: Node3D
var pivot: Node3D
var cam: Camera3D
var sun: DirectionalLight3D
var hud: Control
var fps: Label

var yaw := 0.0
var pitch := -0.3
var stick_id := -1
var stick_origin := Vector2.ZERO
var stick_vec := Vector2.ZERO
var look_id := -1
var jump_req := false


func _ready() -> void:
	_make_env()
	_make_ground()
	_make_city()
	_make_player()
	_make_hud()


func _make_env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.25, 0.45, 0.8)
	sm.sky_horizon_color = Color(0.7, 0.8, 0.9)
	sm.ground_horizon_color = Color(0.7, 0.8, 0.9)
	sm.ground_bottom_color = Color(0.3, 0.3, 0.28)
	sky.sky_material = sm
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.8, 0.9)
	env.fog_density = 0.004
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	sun.light_energy = 1.2
	add_child(sun)


func _make_ground() -> void:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(600, 2, 600)
	col.shape = shape
	col.position = Vector3(0, -1, 0)
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(600, 600)
	mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.62, 0.3)
	mat.roughness = 1.0
	var nt := NoiseTexture2D.new()
	var noise := FastNoiseLite.new()
	noise.frequency = 0.04
	nt.noise = noise
	nt.seamless = true
	mat.albedo_texture = nt
	mat.uv1_scale = Vector3(40, 40, 1)
	mi.material_override = mat
	body.add_child(mi)
	add_child(body)


func _make_city() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for ix in range(-4, 5):
		for iz in range(-4, 5):
			if ix == 0 and iz == 0:
				continue
			var w := rng.randf_range(8.0, 12.0)
			var d := rng.randf_range(8.0, 12.0)
			var h := rng.randf_range(6.0, 20.0)
			var body := StaticBody3D.new()
			body.position = Vector3(ix * 20.0, h * 0.5, iz * 20.0)
			var col := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(w, h, d)
			col.shape = shape
			body.add_child(col)
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(w, h, d)
			mi.mesh = bm
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color.from_hsv(rng.randf_range(0.06, 0.1), rng.randf_range(0.15, 0.35), rng.randf_range(0.7, 0.9))
			mat.roughness = 0.9
			mi.material_override = mat
			body.add_child(mi)
			add_child(body)


func _make_player() -> void:
	player = CharacterBody3D.new()
	player.position = Vector3(0, 0.2, 8)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	player.add_child(cs)
	model = Node3D.new()
	var body := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.4
	cm.height = 1.8
	body.mesh = cm
	body.position = Vector3(0, 0.9, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.08, 0.1)
	body.material_override = mat
	model.add_child(body)
	var nose := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.2, 0.2, 0.3)
	nose.mesh = bm
	nose.position = Vector3(0, 1.4, -0.4)
	model.add_child(nose)
	player.add_child(model)
	add_child(player)
	pivot = Node3D.new()
	add_child(pivot)
	cam = Camera3D.new()
	cam.position = Vector3(0, 0, 4.5)
	cam.fov = 65.0
	pivot.add_child(cam)
	cam.make_current()


func _make_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.draw.connect(_on_hud_draw)
	layer.add_child(hud)
	fps = Label.new()
	fps.position = Vector2(12, 8)
	fps.add_theme_color_override("font_color", Color.WHITE)
	fps.add_theme_color_override("font_outline_color", Color.BLACK)
	fps.add_theme_constant_override("outline_size", 4)
	layer.add_child(fps)


func _jump_center() -> Vector2:
	return Vector2(hud.size.x - 130.0, hud.size.y - 130.0)


func _on_hud_draw() -> void:
	var base := stick_origin if stick_id != -1 else Vector2(150.0, hud.size.y - 150.0)
	hud.draw_circle(base, STICK_R, Color(1, 1, 1, 0.12))
	hud.draw_arc(base, STICK_R, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
	hud.draw_circle(base + stick_vec * STICK_R, 34.0, Color(1, 1, 1, 0.35))
	var jc := _jump_center()
	hud.draw_circle(jc, 62.0, Color(1, 1, 1, 0.18))
	hud.draw_arc(jc, 62.0, 0.0, TAU, 48, Color(1, 1, 1, 0.45), 3.0)


func _input(event: InputEvent) -> void:
	var half := hud.size.x * 0.5
	if event is InputEventScreenTouch:
		if event.pressed:
			if event.position.distance_to(_jump_center()) < 85.0:
				jump_req = true
			elif event.position.x < half and stick_id == -1:
				stick_id = event.index
				stick_origin = event.position
				stick_vec = Vector2.ZERO
			elif event.position.x >= half and look_id == -1:
				look_id = event.index
		else:
			if event.index == stick_id:
				stick_id = -1
				stick_vec = Vector2.ZERO
			if event.index == look_id:
				look_id = -1
	elif event is InputEventScreenDrag:
		if event.index == stick_id:
			var dv: Vector2 = (event.position - stick_origin) / STICK_R
			stick_vec = dv.limit_length(1.0)
		elif event.index == look_id:
			yaw -= event.relative.x * 0.005
			pitch = clampf(pitch - event.relative.y * 0.005, -1.2, 0.4)


func _physics_process(delta: float) -> void:
	var v := Vector3(stick_vec.x, 0.0, stick_vec.y)
	var dir := Basis(Vector3.UP, yaw) * v
	var spd := WALK
	if stick_vec.length() > 0.9:
		spd = RUN
	player.velocity.x = dir.x * spd
	player.velocity.z = dir.z * spd
	if player.is_on_floor():
		if jump_req:
			player.velocity.y = JUMP_V
		else:
			player.velocity.y = -1.0
	else:
		player.velocity.y -= GRAVITY * delta
	jump_req = false
	player.move_and_slide()
	if dir.length() > 0.1:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(-dir.x, -dir.z), minf(1.0, 12.0 * delta))
	pivot.position = player.position + Vector3(0, 1.5, 0)
	pivot.rotation = Vector3(pitch, yaw, 0)


func _process(_delta: float) -> void:
	fps.text = "FPS %d  |  тест сборки v0.1" % Engine.get_frames_per_second()
	hud.queue_redraw()
