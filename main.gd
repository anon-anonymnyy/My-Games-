extends Node3D
# «Саша на борде» — сборка 1 «Двор»

const WALK := 5.0
const RUN := 8.5
const SKATE_MAX := 12.0
const GRAVITY := 24.0
const JUMP_V := 8.0
const STICK_R := 90.0
const MODEL_SCALE := 0.89
const SKATE_LIFT := 0.14
const LOOPING := ["idle", "walk", "run", "fall", "skate_ride", "skate_push"]
const SAVE_PATH := "user://save.json"

var player: CharacterBody3D
var visual: Node3D
var model: Node3D
var board: Node3D
var anim: AnimationPlayer
var cam_pivot: Node3D
var cam: Camera3D
var hud: Control

var state := "select"   # select / play
var char_id := ""
var coins := 0
var streak := 0
var last_day := 0
var popup := false
var popup_reward := 0

var yaw := 0.0
var pitch := -0.2
var heading := 0.0
var skating := false
var skate_speed := 0.0
var vel := Vector3.ZERO
var was_on_floor := true
var land_t := 0.0
var punch_t := 0.0
var punch_n := 0
var trick_t := 0.0
var cur_anim := ""
var prev_pos := Vector3.ZERO
var cur_pos := Vector3.ZERO

var stick_id := -1
var stick_origin := Vector2.ZERO
var stick_pos := Vector2.ZERO
var stick_vec := Vector2.ZERO
var look_id := -1
var coin_nodes: Array = []
var font: Font

func _ready() -> void:
	font = ThemeDB.fallback_font
	_load_save()
	_build_env()
	_build_world()
	_build_player()
	_build_hud()
	_check_daily()
	if char_id != "":
		_spawn_model(char_id)
		state = "play"

# ---------------- сохранение ----------------
func _load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) == TYPE_DICTIONARY:
		coins = int(data.get("coins", 0))
		streak = int(data.get("streak", 0))
		last_day = int(data.get("last_day", 0))
		char_id = str(data.get("char", ""))

func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"coins": coins, "streak": streak, "last_day": last_day, "char": char_id}))

func _check_daily() -> void:
	var today := int(Time.get_unix_time_from_system() / 86400.0)
	if last_day == today:
		return
	if last_day == today - 1:
		streak += 1
	else:
		streak = 1
	last_day = today
	popup_reward = 100 * mini(streak, 7)
	popup = true
	_save()

# ---------------- окружение ----------------
func _build_env() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.25, 0.5, 0.85)
	sky_mat.sky_horizon_color = Color(0.75, 0.85, 0.95)
	sky_mat.ground_horizon_color = Color(0.75, 0.85, 0.95)
	sky_mat.ground_bottom_color = Color(0.5, 0.6, 0.5)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color(0.78, 0.86, 0.95)
	env.fog_density = 0.004
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.5
	add_child(sun)

func _mat(c: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

func _box(pos: Vector3, size: Vector3, c: Color, collide := true, rot := Vector3.ZERO) -> Node3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation = rot
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c)
	body.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		body.add_child(cs)
	add_child(body)
	return body

func _tree(x: float, z: float, h := 4.0) -> void:
	var trunk := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.18
	cm.bottom_radius = 0.25
	cm.height = h * 0.5
	trunk.mesh = cm
	trunk.material_override = _mat(Color(0.4, 0.27, 0.15))
	trunk.position = Vector3(x, h * 0.25, z)
	add_child(trunk)
	var crown := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = h * 0.4
	sm.height = h * 0.8
	crown.mesh = sm
	crown.material_override = _mat(Color(0.2, 0.55, 0.2))
	crown.position = Vector3(x, h * 0.75, z)
	add_child(crown)
	var col := StaticBody3D.new()
	col.position = Vector3(x, h * 0.25, z)
	var cs := CollisionShape3D.new()
	var shp := CylinderShape3D.new()
	shp.radius = 0.25
	shp.height = h * 0.5
	cs.shape = shp
	col.add_child(cs)
	add_child(col)

func _house(x: float, z: float, w: float, d: float, h: float, wall: Color, roof: Color, face_z: float) -> void:
	_box(Vector3(x, h * 0.5, z), Vector3(w, h, d), wall)
	var rm := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(w + 0.8, 2.2, d + 0.8)
	rm.mesh = pm
	rm.material_override = _mat(roof)
	rm.position = Vector3(x, h + 1.1, z)
	add_child(rm)
	# дверь и окна на стороне face_z (+1 или -1)
	var fz := z + face_z * (d * 0.5 + 0.03)
	_box(Vector3(x, 1.1, fz), Vector3(1.2, 2.2, 0.08), Color(0.45, 0.28, 0.15), false)
	_box(Vector3(x - w * 0.3, h * 0.55, fz), Vector3(1.3, 1.2, 0.08), Color(0.6, 0.8, 0.95), false)
	_box(Vector3(x + w * 0.3, h * 0.55, fz), Vector3(1.3, 1.2, 0.08), Color(0.6, 0.8, 0.95), false)

func _build_world() -> void:
	# земля
	var ground := _box(Vector3(0, -0.5, 0), Vector3(400, 1, 400), Color(0.35, 0.62, 0.3))
	var gm := (ground.get_child(0) as MeshInstance3D).material_override as StandardMaterial3D
	var nt := NoiseTexture2D.new()
	var noise := FastNoiseLite.new()
	noise.frequency = 0.05
	nt.noise = noise
	nt.seamless = true
	gm.albedo_texture = nt
	gm.uv1_scale = Vector3(30, 30, 1)
	# дорожка во дворе, тротуар, дорога «Липовая»
	_box(Vector3(0, 0.02, 4), Vector3(3, 0.04, 12), Color(0.75, 0.72, 0.65), false)
	_box(Vector3(0, 0.02, 12), Vector3(200, 0.04, 4), Color(0.72, 0.72, 0.74))
	_box(Vector3(0, 0.02, 20), Vector3(200, 0.04, 10), Color(0.25, 0.25, 0.28))
	for i in range(-9, 10):
		_box(Vector3(i * 10.0, 0.05, 20), Vector3(4, 0.02, 0.25), Color(0.95, 0.95, 0.9), false)
	_box(Vector3(0, 0.02, 28), Vector3(200, 0.04, 4), Color(0.72, 0.72, 0.74))
	# дом бабушки и двор
	_house(-4, -9, 11, 7, 4.5, Color(0.93, 0.85, 0.65), Color(0.6, 0.2, 0.15), 1.0)
	# забор
	var fc := Color(0.55, 0.38, 0.2)
	_box(Vector3(0, 0.6, -13), Vector3(30, 1.2, 0.15), fc)
	_box(Vector3(-15, 0.6, -1.5), Vector3(0.15, 1.2, 23), fc)
	_box(Vector3(15, 0.6, -1.5), Vector3(0.15, 1.2, 23), fc)
	_box(Vector3(-8.75, 0.6, 10), Vector3(12.5, 1.2, 0.15), fc)
	_box(Vector3(8.75, 0.6, 10), Vector3(12.5, 1.2, 0.15), fc)
	# деревья
	_tree(-12, 4, 4.5)
	_tree(11, -6, 5.0)
	_tree(12, 6, 4.0)
	_tree(-11, -11, 4.5)
	for i in range(-6, 7):
		if i % 2 == 0:
			_tree(i * 14.0, 14.5, 4.0)
	# соседние дома
	var wc := [Color(0.85, 0.6, 0.55), Color(0.6, 0.75, 0.85), Color(0.9, 0.85, 0.5), Color(0.7, 0.85, 0.65)]
	for i in range(-4, 5):
		if i == 0:
			continue
		_house(i * 22.0, -9.0, 10, 7, 4.2 + (i % 2) * 0.8, wc[absi(i) % 4], Color(0.35, 0.25, 0.25), 1.0)
		_house(i * 22.0 + 6, 36.0, 10, 7, 5.0, wc[(absi(i) + 1) % 4], Color(0.3, 0.3, 0.38), -1.0)
	# скейт-элементы во дворе
	_box(Vector3(6, 0.45, 3), Vector3(3, 0.3, 4), Color(0.7, 0.55, 0.35), true, Vector3(0.26, 0, 0))
	_box(Vector3(-7, 0.3, 4), Vector3(4, 0.6, 3), Color(0.6, 0.6, 0.65))
	_box(Vector3(-7, 0.3, 7.2), Vector3(3, 0.3, 3), Color(0.7, 0.55, 0.35), true, Vector3(-0.2, 0, 0))
	_box(Vector3(2, 0.35, -4), Vector3(0.12, 0.7, 0.12), Color(0.8, 0.2, 0.2))
	_box(Vector3(6, 0.65, -4), Vector3(8, 0.1, 0.1), Color(0.8, 0.2, 0.2))
	# пандус на улице
	_box(Vector3(20, 0.45, 12), Vector3(4, 0.3, 4), Color(0.7, 0.55, 0.35), true, Vector3(0.26, 0, 0))
	_box(Vector3(30, 0.3, 12), Vector3(5, 0.6, 3), Color(0.6, 0.6, 0.65))
	# монеты
	var spots := [Vector3(3, 0.8, 6), Vector3(-3, 0.8, 6), Vector3(0, 0.8, 9), Vector3(10, 0.8, 0), Vector3(-10, 0.8, 0),
		Vector3(6, 2.2, 0.6), Vector3(-7, 1.2, 4), Vector3(8, 0.8, -4), Vector3(-9, 0.8, 8), Vector3(0, 0.8, -3),
		Vector3(5, 0.8, 12), Vector3(15, 0.8, 12), Vector3(25, 0.8, 12), Vector3(-10, 0.8, 12), Vector3(-20, 0.8, 12),
		Vector3(30, 1.5, 12), Vector3(0, 0.8, 18), Vector3(12, 0.8, 18), Vector3(-12, 0.8, 18), Vector3(24, 0.8, 18)]
	for s in spots:
		var pivot := Node3D.new()
		pivot.position = s
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.28
		cm.bottom_radius = 0.28
		cm.height = 0.06
		mi.mesh = cm
		mi.rotation.x = PI / 2.0
		var m := _mat(Color(1, 0.8, 0.1), 0.3)
		m.emission_enabled = true
		m.emission = Color(0.6, 0.45, 0.0)
		mi.material_override = m
		pivot.add_child(mi)
		add_child(pivot)
		coin_nodes.append(pivot)

# ---------------- игрок ----------------
func _build_player() -> void:
	player = CharacterBody3D.new()
	player.position = Vector3(0, 0.1, 6)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	cs.shape = cap
	cs.position = Vector3(0, 0.85, 0)
	player.add_child(cs)
	add_child(player)
	visual = Node3D.new()
	visual.top_level = true
	player.add_child(visual)
	prev_pos = player.position
	cur_pos = player.position
	var bscene: PackedScene = load("res://skateboard.glb")
	if bscene != null:
		board = bscene.instantiate()
		board.visible = false
		visual.add_child(board)
	cam_pivot = Node3D.new()
	add_child(cam_pivot)
	cam = Camera3D.new()
	cam.position = Vector3(0, 0, 4.5)
	cam.fov = 70
	cam.current = true
	cam_pivot.add_child(cam)
	cam_pivot.global_position = player.global_position + Vector3(0, 1.5, 0)
	yaw = PI

func _spawn_model(id: String) -> void:
	if model != null:
		model.queue_free()
		model = null
		anim = null
	char_id = id
	var path := "res://sasha_boy_rigged.glb" if id == "boy" else "res://sasha_girl_rigged.glb"
	var sc: PackedScene = load(path)
	if sc == null:
		return
	model = sc.instantiate()
	model.scale = Vector3(MODEL_SCALE, MODEL_SCALE, MODEL_SCALE)
	model.position = Vector3(0, MODEL_SCALE, 0)
	visual.add_child(model)
	anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim != null:
		for n in anim.get_animation_list():
			var a: Animation = anim.get_animation(n)
			a.loop_mode = Animation.LOOP_LINEAR if (n in LOOPING) else Animation.LOOP_NONE
	cur_anim = ""
	_play("idle")
	_save()

func _play(n: String) -> void:
	if anim == null or cur_anim == n:
		return
	if not anim.has_animation(n):
		return
	anim.play(n, 0.15)
	cur_anim = n

# ---------------- HUD ----------------
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)
	hud.draw.connect(_hud_draw)

func _vs() -> Vector2:
	return get_viewport().get_visible_rect().size

func _btn_jump() -> Vector2:
	return _vs() - Vector2(130, 130)
func _btn_board() -> Vector2:
	return _vs() - Vector2(290, 110)
func _btn_hit() -> Vector2:
	return _vs() - Vector2(130, 290)
func _btn_swap() -> Rect2:
	return Rect2(_vs().x - 190, 20, 170, 60)
func _btn_claim() -> Rect2:
	var s := _vs()
	return Rect2(s.x * 0.5 - 130, s.y * 0.5 + 90, 260, 70)
func _sel_rect(i: int) -> Rect2:
	var s := _vs()
	return Rect2(s.x * 0.5 - 420 + i * 440, s.y * 0.5 - 170, 400, 340)

func _text(t: String, p: Vector2, size: int, c := Color.WHITE) -> void:
	hud.draw_string(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, c)

func _text_c(t: String, center: Vector2, size: int, c := Color.WHITE) -> void:
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	hud.draw_string(font, center + Vector2(-w * 0.5, size * 0.35), t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, c)

func _btn_draw(p: Vector2, r: float, c: Color) -> void:
	hud.draw_circle(p, r, c)
	hud.draw_arc(p, r, 0, TAU, 32, Color(1, 1, 1, 0.8), 3.0)

func _hud_draw() -> void:
	var s := _vs()
	if state == "select":
		hud.draw_rect(Rect2(Vector2.ZERO, s), Color(0.1, 0.12, 0.2, 0.92))
		_text_c("Саша на борде", Vector2(s.x * 0.5, s.y * 0.5 - 230), 52)
		_text_c("Выбери героя", Vector2(s.x * 0.5, s.y * 0.5 - 195), 26, Color(0.8, 0.85, 1))
		for i in range(2):
			var r := _sel_rect(i)
			hud.draw_rect(r, Color(0.25, 0.3, 0.5), true)
			hud.draw_rect(r, Color(1, 1, 1, 0.6), false, 3.0)
			_text_c("Саша", r.get_center() + Vector2(0, -30), 56)
			_text_c("парень" if i == 0 else "девушка", r.get_center() + Vector2(0, 40), 34, Color(0.9, 0.9, 0.5))
		return
	# монеты и место
	hud.draw_rect(Rect2(20, 20, 260, 56), Color(0, 0, 0, 0.45), true)
	_text("%d ₽" % coins, Vector2(36, 60), 34, Color(1, 0.9, 0.3))
	_text("Липовая", Vector2(22, 100), 24, Color(1, 1, 1, 0.8))
	_text("FPS %d" % Engine.get_frames_per_second(), Vector2(22, 130), 20, Color(1, 1, 1, 0.6))
	hud.draw_rect(_btn_swap(), Color(0, 0, 0, 0.45), true)
	_text_c("Сменить", _btn_swap().get_center(), 26)
	# джойстик
	if stick_id != -1:
		hud.draw_circle(stick_origin, STICK_R, Color(1, 1, 1, 0.15))
		hud.draw_circle(stick_origin + stick_vec * STICK_R, 40, Color(1, 1, 1, 0.45))
	# кнопки
	_btn_draw(_btn_jump(), 62, Color(0.15, 0.2, 0.35, 0.55))
	_text_c("Прыжок" if not (skating and not player.is_on_floor()) else "Трюк", _btn_jump(), 22)
	_btn_draw(_btn_board(), 52, Color(0.9, 0.65, 0.1, 0.7) if skating else Color(0.15, 0.2, 0.35, 0.55))
	_text_c("Скейт", _btn_board(), 22)
	_btn_draw(_btn_hit(), 52, Color(0.7, 0.15, 0.15, 0.6))
	_text_c("Удар", _btn_hit(), 22)
	# ежедневная награда
	if popup:
		hud.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.6))
		var pr := Rect2(s.x * 0.5 - 300, s.y * 0.5 - 200, 600, 400)
		hud.draw_rect(pr, Color(0.18, 0.22, 0.38), true)
		hud.draw_rect(pr, Color(1, 0.85, 0.3), false, 4.0)
		_text_c("Ежедневная награда", Vector2(s.x * 0.5, pr.position.y + 45), 38)
		_text_c("Дней подряд: %d" % streak, Vector2(s.x * 0.5, pr.position.y + 85), 26, Color(0.8, 0.85, 1))
		for i in range(7):
			var cx := s.x * 0.5 - 240 + i * 80.0
			var on := i < mini(streak, 7)
			hud.draw_circle(Vector2(cx, pr.position.y + 145), 30, Color(1, 0.8, 0.2) if on else Color(0.35, 0.38, 0.5))
			_text_c(str(i + 1), Vector2(cx, pr.position.y + 145), 26, Color(0.1, 0.1, 0.1) if on else Color.WHITE)
		_text_c("+%d ₽" % popup_reward, Vector2(s.x * 0.5, pr.position.y + 220), 54, Color(1, 0.9, 0.3))
		var br := _btn_claim()
		hud.draw_rect(br, Color(0.3, 0.7, 0.3), true)
		_text_c("Забрать", br.get_center(), 36)

# ---------------- ввод ----------------
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			_on_press(e.index, e.position)
		else:
			if e.index == stick_id:
				stick_id = -1
				stick_vec = Vector2.ZERO
			if e.index == look_id:
				look_id = -1
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == stick_id:
			stick_pos = d.position
			var v := (stick_pos - stick_origin) / STICK_R
			stick_vec = v.limit_length(1.0)
		elif d.index == look_id:
			yaw -= d.relative.x * 0.005
			pitch = clampf(pitch - d.relative.y * 0.005, -1.2, 0.4)

func _on_press(idx: int, p: Vector2) -> void:
	if state == "select":
		for i in range(2):
			if _sel_rect(i).has_point(p):
				_spawn_model("boy" if i == 0 else "girl")
				state = "play"
		return
	if popup:
		if _btn_claim().has_point(p):
			coins += popup_reward
			popup = false
			_save()
		return
	if _btn_swap().has_point(p):
		state = "select"
		return
	if p.distance_to(_btn_jump()) < 85:
		_do_jump()
		return
	if p.distance_to(_btn_board()) < 75:
		_toggle_skate()
		return
	if p.distance_to(_btn_hit()) < 75:
		_do_hit()
		return
	if p.x < _vs().x * 0.5 and stick_id == -1:
		stick_id = idx
		stick_origin = p
		stick_pos = p
		stick_vec = Vector2.ZERO
	elif look_id == -1:
		look_id = idx

func _toggle_skate() -> void:
	skating = not skating
	skate_speed = 0.0
	if board != null:
		board.visible = skating
	cam.position.z = 5.5 if skating else 4.5
	cur_anim = ""

func _do_jump() -> void:
	if player.is_on_floor():
		vel.y = JUMP_V
		_play("jump_start")
	elif skating and trick_t <= 0.0:
		trick_t = 0.55

func _do_hit() -> void:
	if skating or punch_t > 0.0:
		return
	punch_n += 1
	if punch_n % 2 == 1:
		punch_t = 0.5
		cur_anim = ""
		_play("punch")
	else:
		punch_t = 0.7
		cur_anim = ""
		_play("kick")

# ---------------- игровой цикл ----------------
func _physics_process(d: float) -> void:
	if state != "play" or model == null:
		return
	var mag := stick_vec.length()
	var dir := Vector3(stick_vec.x, 0, stick_vec.y).rotated(Vector3.UP, yaw)
	var on_floor := player.is_on_floor()
	if not skating:
		var tgt := (RUN if mag > 0.9 else WALK) * minf(mag * 1.2, 1.0)
		if punch_t > 0.0:
			tgt *= 0.25
		vel.x = move_toward(vel.x, dir.x * tgt, 45.0 * d)
		vel.z = move_toward(vel.z, dir.z * tgt, 45.0 * d)
		if mag > 0.1 and punch_t <= 0.0:
			heading = lerp_angle(heading, atan2(dir.x, dir.z), minf(1.0, 14.0 * d))
	else:
		if mag > 0.15:
			heading = lerp_angle(heading, atan2(dir.x, dir.z), minf(1.0, 3.0 * d))
			skate_speed = move_toward(skate_speed, SKATE_MAX * mag, 6.0 * d)
		else:
			skate_speed = move_toward(skate_speed, 0.0, 3.0 * d)
		vel.x = sin(heading) * skate_speed
		vel.z = cos(heading) * skate_speed
	if not on_floor:
		vel.y -= GRAVITY * d
	elif vel.y < 0.0:
		vel.y = -1.0
	player.velocity = vel
	player.move_and_slide()
	vel = player.velocity
	prev_pos = cur_pos
	cur_pos = player.global_position
	if skating:
		skate_speed = Vector2(vel.x, vel.z).length() if skate_speed > 0.0 else 0.0
	if player.is_on_floor() and not was_on_floor:
		land_t = 0.25
	was_on_floor = player.is_on_floor()
	if player.position.y < -20.0:
		player.position = Vector3(0, 0.5, 6)
		vel = Vector3.ZERO
		prev_pos = player.position
		cur_pos = player.position
	# анимация
	punch_t = maxf(0.0, punch_t - d)
	land_t = maxf(0.0, land_t - d)
	var hs := Vector2(vel.x, vel.z).length()
	if punch_t > 0.0:
		pass
	elif not player.is_on_floor():
		if vel.y > 0.5:
			_play("jump_start")
		else:
			_play("fall")
	elif land_t > 0.0 and not skating:
		_play("land")
	elif skating:
		if mag > 0.15 and skate_speed < SKATE_MAX * 0.7:
			_play("skate_push")
		else:
			_play("skate_ride")
	elif hs > 6.0:
		_play("run")
	elif hs > 0.5:
		_play("walk")
	else:
		_play("idle")

func _process(d: float) -> void:
	for c in coin_nodes:
		if c != null and c.visible:
			c.rotation.y += 2.5 * d
			if state == "play" and player != null and c.global_position.distance_to(player.global_position + Vector3(0, 0.9, 0)) < 1.1:
				c.visible = false
				coins += 10
				_save()
	if player == null or model == null:
		return
	visual.rotation.y = lerp_angle(visual.rotation.y, heading, minf(1.0, 18.0 * d))
	var lift := SKATE_LIFT if skating else 0.0
	model.position.y = lerpf(model.position.y, MODEL_SCALE + lift, minf(1.0, 15.0 * d))
	if board != null and skating:
		if trick_t > 0.0:
			trick_t = maxf(0.0, trick_t - d)
			board.rotation.z = (1.0 - trick_t / 0.55) * TAU
		else:
			board.rotation.z = 0.0
	cam_pivot.rotation = Vector3(pitch, yaw, 0)
	var ip: Vector3 = prev_pos.lerp(cur_pos, Engine.get_physics_interpolation_fraction())
	visual.global_position = ip
	var target: Vector3 = ip + Vector3(0, 1.5, 0)
	cam_pivot.global_position = cam_pivot.global_position.lerp(target, minf(1.0, 12.0 * d))
	hud.queue_redraw()
