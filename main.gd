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
const TRICKS := [
	{"id": "kickflip", "name": "Кикфлип", "pts": 300},
	{"id": "shuvit", "name": "Шув-ит", "pts": 250},
	{"id": "heelflip", "name": "Хилфлип", "pts": 400},
	{"id": "flip360", "name": "360 флип", "pts": 700}]
const QUESTS := [
	{"t": "Собери 10 монет", "k": "coins_got", "n": 10, "r": 100, "u": ""},
	{"t": "Проедь 300 м на скейте", "k": "dist", "n": 300, "r": 150, "u": "shuvit"},
	{"t": "Сделай 5 трюков", "k": "tricks", "n": 5, "r": 200, "u": ""},
	{"t": "Собери 40 монет", "k": "coins_got", "n": 40, "r": 300, "u": ""},
	{"t": "Сделай 15 трюков", "k": "tricks", "n": 15, "r": 400, "u": "heelflip"},
	{"t": "Набери 3000 очков за трюки", "k": "score", "n": 3000, "r": 600, "u": "flip360"},
	{"t": "Проедь 2000 м на скейте", "k": "dist", "n": 2000, "r": 800, "u": ""},
	{"t": "Заедь в скейт-парк (справа по улице)", "k": "park", "n": 1, "r": 200, "u": ""},
	{"t": "Набери 8000 очков за трюки", "k": "score", "n": 8000, "r": 1000, "u": ""}]
const UPGRADES := [
	{"name": "Покрасить забор", "cost": 300, "inc": 30},
	{"name": "Новая крыша", "cost": 600, "inc": 60},
	{"name": "Крыльцо и веранда", "cost": 1200, "inc": 120},
	{"name": "Мастерская во дворе", "cost": 2500, "inc": 250},
	{"name": "Своя лавка", "cost": 5000, "inc": 500}]
const MAX_OFFLINE_H := 8.0

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
var coin_respawn: Array = []
var brake_id := -1
var tricks_open: Array = ["kickflip"]
var trick_sel := 0
var trick_active := false
var trick_dur := 0.6
var trick_def: Dictionary = {}
var stats: Dictionary = {"coins_got": 0, "dist": 0.0, "tricks": 0, "score": 0, "park": 0}
var quest_i := 0
var owned: Array = []
var last_collect := 0
var panel := ""
var toast := ""
var toast_t := 0.0
var quest_timer := 0.0
var fence_mats: Array = []
var roof_mat: StandardMaterial3D
var upgrade_nodes: Dictionary = {}
var trick_pending := 0
var font: Font

func _ready() -> void:
	font = ThemeDB.fallback_font
	_load_save()
	if last_collect == 0:
		last_collect = int(Time.get_unix_time_from_system())
	_build_env()
	_build_world()
	_build_skatepark()
	_build_player()
	_build_hud()
	_apply_upgrades()
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
		tricks_open = data.get("tricks_open", ["kickflip"])
		quest_i = int(data.get("quest_i", 0))
		owned = data.get("owned", [])
		last_collect = int(data.get("last_collect", 0))
		var st = data.get("stats", {})
		if typeof(st) == TYPE_DICTIONARY:
			for k in stats.keys():
				stats[k] = st.get(k, stats[k])

func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"coins": coins, "streak": streak, "last_day": last_day, "char": char_id, "tricks_open": tricks_open, "quest_i": quest_i, "owned": owned, "last_collect": last_collect, "stats": stats}))

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

func _house(x: float, z: float, w: float, d: float, h: float, wall: Color, roof: Color, face_z: float) -> MeshInstance3D:
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
	return rm

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
	var grandma_roof := _house(-4, -9, 11, 7, 4.5, Color(0.93, 0.85, 0.65), Color(0.6, 0.2, 0.15), 1.0)
	roof_mat = grandma_roof.material_override as StandardMaterial3D
	# забор
	var fc := Color(0.55, 0.38, 0.2)
	fence_mats.append((_box(Vector3(0, 0.6, -13), Vector3(30, 1.2, 0.15), fc)).get_child(0).material_override)
	fence_mats.append((_box(Vector3(-15, 0.6, -1.5), Vector3(0.15, 1.2, 23), fc)).get_child(0).material_override)
	fence_mats.append((_box(Vector3(15, 0.6, -1.5), Vector3(0.15, 1.2, 23), fc)).get_child(0).material_override)
	fence_mats.append((_box(Vector3(-8.75, 0.6, 10), Vector3(12.5, 1.2, 0.15), fc)).get_child(0).material_override)
	fence_mats.append((_box(Vector3(8.75, 0.6, 10), Vector3(12.5, 1.2, 0.15), fc)).get_child(0).material_override)
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
		coin_respawn.append(0.0)
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

# ---------------- скейт-парк ----------------
func _in_park() -> bool:
	return player != null and player.global_position.x > 52.0 and player.global_position.x < 108.0 and player.global_position.z < 10.0

func _teleport(p: Vector3) -> void:
	player.global_position = p
	vel = Vector3.ZERO
	skate_speed = 0.0
	prev_pos = p
	cur_pos = p
	heading = PI if p.x > 50.0 else 0.0
	yaw = PI
	cam_pivot.global_position = p + Vector3(0, 1.5, 0)

func _add_coin(pos: Vector3) -> void:
	var pivot := Node3D.new()
	pivot.position = pos
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
	coin_respawn.append(0.0)

func _quarter(pos: Vector3, rot_y: float, width: float, r: float, c: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 10
	for k in range(n):
		var a0 := (PI / 2.0) * float(k) / float(n)
		var a1 := (PI / 2.0) * float(k + 1) / float(n)
		var z0 := -r * sin(a0)
		var y0 := r * (1.0 - cos(a0))
		var z1 := -r * sin(a1)
		var y1 := r * (1.0 - cos(a1))
		var n0 := Vector3(0, cos(a0), sin(a0))
		var n1 := Vector3(0, cos(a1), sin(a1))
		var hw := width * 0.5
		var A0 := Vector3(-hw, y0, z0)
		var B0 := Vector3(hw, y0, z0)
		var A1 := Vector3(-hw, y1, z1)
		var B1 := Vector3(hw, y1, z1)
		for v in [[A0, n0], [A1, n1], [B0, n0], [B0, n0], [A1, n1], [B1, n1]]:
			st.set_normal(v[1])
			st.add_vertex(v[0])
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := _mat(c)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.position = pos
	mi.rotation.y = rot_y
	add_child(mi)
	mi.create_trimesh_collision()
	# боковые стенки и платформа сверху
	var plat := _box(Vector3(0, r, -r - 0.5), Vector3(width, 0.2, 1.0), Color(0.55, 0.55, 0.6))
	remove_child(plat)
	mi.add_child(plat)
	plat.position = Vector3(0, r - 0.1, -r - 0.5)

func _kicker(x: float, z: float, w: float, ry: float, c: Color, y := 0.3) -> void:
	_box(Vector3(x, y, z), Vector3(w, 0.3, 3.0), c, true, Vector3(0.26, ry, 0))

func _build_skatepark() -> void:
	var cx := 80.0
	# площадка
	_box(Vector3(cx, 0.03, -10), Vector3(52, 0.06, 42), Color(0.62, 0.62, 0.66))
	# низкая стенка по периметру, въезд со стороны улицы
	var wc := Color(0.5, 0.5, 0.55)
	_box(Vector3(cx, 0.4, -31), Vector3(52, 0.8, 0.4), wc)
	_box(Vector3(cx - 26, 0.4, -10), Vector3(0.4, 0.8, 42), wc)
	_box(Vector3(cx + 26, 0.4, -10), Vector3(0.4, 0.8, 42), wc)
	_box(Vector3(cx - 17.5, 0.4, 11), Vector3(17, 0.8, 0.4), wc)
	_box(Vector3(cx + 17.5, 0.4, 11), Vector3(17, 0.8, 0.4), wc)
	# вывеска
	var lb := Label3D.new()
	lb.text = "СКЕЙТ-ПАРК"
	lb.font_size = 160
	lb.pixel_size = 0.012
	lb.position = Vector3(cx, 4.5, 11)
	lb.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	lb.modulate = Color(1, 0.85, 0.2)
	lb.outline_modulate = Color(0.1, 0.1, 0.1)
	add_child(lb)
	_box(Vector3(cx - 4, 2.0, 11), Vector3(0.3, 4.0, 0.3), Color(0.3, 0.3, 0.35), false)
	_box(Vector3(cx + 4, 2.0, 11), Vector3(0.3, 4.0, 0.3), Color(0.3, 0.3, 0.35), false)
	# большие рампы-четвертьпайпы
	_quarter(Vector3(cx, 0.06, -26), 0.0, 16.0, 2.2, Color(0.7, 0.45, 0.3))
	_quarter(Vector3(cx - 22, 0.06, -10), PI / 2.0, 14.0, 2.2, Color(0.35, 0.5, 0.75))
	_quarter(Vector3(cx + 22, 0.06, -10), -PI / 2.0, 14.0, 2.2, Color(0.35, 0.5, 0.75))
	# фанбокс по центру
	_box(Vector3(cx, 0.35, -10), Vector3(8, 0.7, 5), Color(0.85, 0.7, 0.3))
	_kicker(cx, -6.05, 5.0, 0.0, Color(0.7, 0.55, 0.35), 0.17)
	_kicker(cx, -13.95, 5.0, PI, Color(0.7, 0.55, 0.35), 0.17)
	# лесенка с перилами
	for i in range(4):
		_box(Vector3(cx + 12, 0.15 + i * 0.3, -18 - i * 1.2), Vector3(4, 0.3 + i * 0.3, 1.2), Color(0.55, 0.55, 0.6))
	_box(Vector3(cx + 14.3, 0.9, -19.8), Vector3(0.1, 0.1, 5.0), Color(0.8, 0.2, 0.2), true, Vector3(0.24, 0, 0))
	# рейлы
	_box(Vector3(cx - 12, 0.55, -18), Vector3(8, 0.1, 0.1), Color(0.8, 0.2, 0.2))
	_box(Vector3(cx - 15.5, 0.27, -18), Vector3(0.1, 0.55, 0.1), Color(0.3, 0.3, 0.35), false)
	_box(Vector3(cx - 8.5, 0.27, -18), Vector3(0.1, 0.55, 0.1), Color(0.3, 0.3, 0.35), false)
	# банк-рампа и мэнуал-пад
	_box(Vector3(cx - 14, 0.2, -2), Vector3(6, 0.4, 3), Color(0.6, 0.6, 0.65))
	_kicker(cx - 14, 0.95, 6.0, 0.0, Color(0.7, 0.55, 0.35), -0.13)
	# входные кикеры
	_kicker(cx + 12, 4.0, 4.0, 0.0, Color(0.7, 0.55, 0.35))
	# монеты
	var cp := [Vector3(cx, 1.4, -10), Vector3(cx, 0.8, -3), Vector3(cx - 8, 0.8, -8), Vector3(cx + 8, 0.8, -6),
		Vector3(cx - 12, 1.2, -18), Vector3(cx + 12, 2.2, -21), Vector3(cx - 14, 1.2, -2), Vector3(cx, 3.0, -24),
		Vector3(cx - 19, 1.8, -10), Vector3(cx + 19, 1.8, -10), Vector3(cx, 0.8, 5), Vector3(cx + 12, 0.8, 7),
		Vector3(cx - 20, 0.8, 4), Vector3(cx + 20, 0.8, 4)]
	for p in cp:
		_add_coin(p)
	# деревья вокруг
	for tp in [Vector2(cx - 32, -20), Vector2(cx + 32, -20), Vector2(cx - 32, 0), Vector2(cx + 32, 0), Vector2(cx, -36)]:
		_tree(tp.x, tp.y, 4.5)

# ---------------- игрок ----------------
func _build_player() -> void:
	player = CharacterBody3D.new()
	player.floor_max_angle = deg_to_rad(70.0)
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
func _btn_brake() -> Vector2:
	return _vs() - Vector2(460, 110)
func _btn_trick() -> Vector2:
	return _vs() - Vector2(300, 270)
func _btn_cycle() -> Vector2:
	return _vs() - Vector2(300, 375)
func _btn_house() -> Rect2:
	return Rect2(_vs().x * 0.5 - 130, 86, 260, 56)
func _pr() -> Rect2:
	var s := _vs()
	return Rect2(s.x * 0.5 - 400, s.y * 0.5 - 250, 800, 500)
func _pr_close() -> Rect2:
	return Rect2(_pr().end.x - 110, _pr().position.y + 12, 98, 50)
func _pr_collect() -> Rect2:
	return Rect2(_pr().end.x - 270, _pr().position.y + 80, 250, 56)
func _pr_row(i: int) -> Rect2:
	return Rect2(_pr().position.x + 20, _pr().position.y + 150 + i * 66, 760, 58)
func _pr_buy(i: int) -> Rect2:
	return Rect2(_pr_row(i).end.x - 170, _pr_row(i).position.y + 6, 160, 46)
func _btn_tp() -> Rect2:
	return Rect2(_vs().x * 0.5 + 150, 86, 200, 56)
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
	hud.draw_rect(_btn_house(), Color(0.45, 0.3, 0.1, 0.8), true)
	hud.draw_rect(_btn_house(), Color(1, 1, 1, 0.6), false, 2.0)
	_text_c("Дом  +%d ₽" % _pending_income(), _btn_house().get_center(), 24)
	hud.draw_rect(_btn_tp(), Color(0.15, 0.35, 0.3, 0.8), true)
	hud.draw_rect(_btn_tp(), Color(1, 1, 1, 0.6), false, 2.0)
	_text_c("В двор" if _in_park() else "В скейт-парк", _btn_tp().get_center(), 22)
	_text(_quest_text(), Vector2(22, 165), 20, Color(1, 0.95, 0.6))
	if toast_t > 0.0:
		var tr := Rect2(s.x * 0.5 - 340, 160, 680, 64)
		hud.draw_rect(tr, Color(0.1, 0.4, 0.15, 0.88), true)
		_text_c(toast, tr.get_center(), 26)
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
	if skating:
		_btn_draw(_btn_brake(), 52, Color(0.8, 0.15, 0.15, 0.75) if brake_id != -1 else Color(0.15, 0.2, 0.35, 0.55))
		_text_c("Тормоз", _btn_brake(), 22)
		_btn_draw(_btn_trick(), 52, Color(0.35, 0.2, 0.55, 0.7))
		_text_c("Трюк", _btn_trick(), 24)
		_btn_draw(_btn_cycle(), 46, Color(0.15, 0.2, 0.35, 0.55))
		_text_c(_trick_name(), _btn_cycle(), 16)
	if panel == "house":
		_draw_house_panel(s)
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

func _draw_house_panel(s: Vector2) -> void:
	hud.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.6))
	var pr := _pr()
	hud.draw_rect(pr, Color(0.2, 0.22, 0.32), true)
	hud.draw_rect(pr, Color(1, 0.85, 0.3), false, 4.0)
	_text_c("Дом бабушки", Vector2(pr.get_center().x, pr.position.y + 40), 38)
	hud.draw_rect(_pr_close(), Color(0.7, 0.2, 0.2), true)
	_text_c("Закрыть", _pr_close().get_center(), 20)
	_text("Доход: %d ₽/час (копится до %d ч)" % [_income_h(), int(MAX_OFFLINE_H)], Vector2(pr.position.x + 24, pr.position.y + 100), 24, Color(0.85, 0.9, 1))
	_text("Накоплено: %d ₽" % _pending_income(), Vector2(pr.position.x + 24, pr.position.y + 130), 24, Color(1, 0.9, 0.3))
	hud.draw_rect(_pr_collect(), Color(0.3, 0.7, 0.3), true)
	_text_c("Забрать", _pr_collect().get_center(), 26)
	for i in range(UPGRADES.size()):
		var r := _pr_row(i)
		hud.draw_rect(r, Color(0.28, 0.3, 0.45), true)
		var u: Dictionary = UPGRADES[i]
		_text("%s  (+%d ₽/час)" % [u["name"], int(u["inc"])], Vector2(r.position.x + 14, r.position.y + 38), 24)
		var b := _pr_buy(i)
		if _has(i):
			hud.draw_rect(b, Color(0.25, 0.25, 0.3), true)
			_text_c("Есть", b.get_center(), 22)
		else:
			var can := coins >= int(u["cost"]) and (i == 0 or _has(i - 1))
			hud.draw_rect(b, Color(0.8, 0.6, 0.1) if can else Color(0.4, 0.35, 0.3), true)
			_text_c("%d ₽" % int(u["cost"]), b.get_center(), 24)

# ---------------- дом, доход, улучшения ----------------
func _has(i: int) -> bool:
	for o in owned:
		if int(o) == i:
			return true
	return false

func _income_h() -> int:
	var t := 0
	for i in range(UPGRADES.size()):
		if _has(i):
			t += int(UPGRADES[i]["inc"])
	return t

func _pending_income() -> int:
	var hrs := minf((Time.get_unix_time_from_system() - float(last_collect)) / 3600.0, MAX_OFFLINE_H)
	return int(maxf(hrs, 0.0) * float(_income_h()))

func _collect_income() -> void:
	var a := _pending_income()
	last_collect = int(Time.get_unix_time_from_system())
	if a > 0:
		coins += a
		_toast("Доход с дома: +%d ₽" % a)
	_save()

func _panel_press(p: Vector2) -> void:
	if _pr_close().has_point(p) or not _pr().has_point(p):
		panel = ""
		return
	if _pr_collect().has_point(p):
		_collect_income()
		return
	for i in range(UPGRADES.size()):
		if _pr_buy(i).has_point(p) and not _has(i):
			var cost := int(UPGRADES[i]["cost"])
			if coins >= cost and (i == 0 or _has(i - 1)):
				_collect_income()
				coins -= cost
				owned.append(i)
				_apply_upgrades()
				_toast("Куплено: %s" % UPGRADES[i]["name"])
				_save()
			else:
				_toast("Не хватает ₽ или нужно предыдущее улучшение")

func _apply_upgrades() -> void:
	if _has(0):
		for m in fence_mats:
			var sm := m as StandardMaterial3D
			if sm != null:
				sm.albedo_color = Color(0.25, 0.5, 0.85)
	if _has(1) and roof_mat != null:
		roof_mat.albedo_color = Color(0.2, 0.45, 0.55)
	if _has(2) and not upgrade_nodes.has(2):
		upgrade_nodes[2] = _box(Vector3(-4, 0.15, -5.0), Vector3(6, 0.3, 2.4), Color(0.62, 0.42, 0.25))
		_box(Vector3(-6.6, 1.2, -4.0), Vector3(0.2, 2.4, 0.2), Color(0.95, 0.95, 0.9), false)
		_box(Vector3(-1.4, 1.2, -4.0), Vector3(0.2, 2.4, 0.2), Color(0.95, 0.95, 0.9), false)
		_box(Vector3(-4, 2.5, -4.6), Vector3(6.4, 0.15, 3.0), Color(0.55, 0.2, 0.15), false)
	if _has(3) and not upgrade_nodes.has(3):
		upgrade_nodes[3] = _box(Vector3(10, 1.2, -9), Vector3(4, 2.4, 3), Color(0.55, 0.58, 0.62))
		_box(Vector3(10, 2.5, -9), Vector3(4.6, 0.2, 3.6), Color(0.3, 0.3, 0.35), false)
		_box(Vector3(10, 1.0, -7.45), Vector3(1.4, 2.0, 0.1), Color(0.35, 0.22, 0.12), false)
	if _has(4) and not upgrade_nodes.has(4):
		upgrade_nodes[4] = _box(Vector3(-10, 1.2, 8.0), Vector3(3.2, 2.4, 2.4), Color(0.95, 0.6, 0.2))
		_box(Vector3(-10, 2.3, 9.4), Vector3(3.6, 0.15, 1.0), Color(0.85, 0.15, 0.15), false)
		_box(Vector3(-10, 1.3, 9.25), Vector3(2.2, 0.9, 0.1), Color(0.95, 0.95, 0.7), false)

# ---------------- задания и трюки ----------------
func _toast(t: String) -> void:
	toast = t
	toast_t = 3.0

func _quest_text() -> String:
	if quest_i >= QUESTS.size():
		return "Все задания выполнены!"
	var q: Dictionary = QUESTS[quest_i]
	return "Задание: %s (%d/%d)" % [q["t"], mini(int(float(stats[q["k"]])), int(q["n"])), int(q["n"])]

func _check_quest() -> void:
	if quest_i >= QUESTS.size():
		return
	var q: Dictionary = QUESTS[quest_i]
	if float(stats[q["k"]]) >= float(q["n"]):
		coins += int(q["r"])
		var msg := "Задание выполнено! +%d ₽" % int(q["r"])
		var u: String = q["u"]
		if u != "" and not (u in tricks_open):
			tricks_open.append(u)
			msg += "  Новый трюк: %s" % _trick_of(u)["name"]
		quest_i += 1
		_toast(msg)
		_save()

func _trick_of(id: String) -> Dictionary:
	for t in TRICKS:
		if t["id"] == id:
			return t
	return TRICKS[0]

func _trick_name() -> String:
	if trick_sel >= tricks_open.size():
		trick_sel = 0
	return str(_trick_of(str(tricks_open[trick_sel]))["name"])

func _do_trick() -> void:
	if not skating or player.is_on_floor() or trick_active or trick_pending > 0:
		return
	if trick_sel >= tricks_open.size():
		trick_sel = 0
	trick_def = _trick_of(str(tricks_open[trick_sel]))
	trick_active = true
	trick_dur = 0.5
	trick_t = trick_dur

func _reset_trick() -> void:
	trick_active = false
	trick_pending = 0
	if board != null:
		board.rotation = Vector3.ZERO

func _on_land() -> void:
	if trick_active and trick_t < 0.25:
		trick_pending = int(trick_def["pts"])
	if trick_pending > 0:
		stats["tricks"] = int(stats["tricks"]) + 1
		stats["score"] = int(stats["score"]) + trick_pending
		var bonus := maxi(trick_pending / 50, 1)
		coins += bonus
		_toast("%s! +%d очков, +%d ₽" % [trick_def["name"], trick_pending, bonus])
		_save()
	elif trick_active:
		_toast("Не докрутил трюк")
	_reset_trick()

# ---------------- ввод ----------------
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			_on_press(e.index, e.position)
		else:
			if e.index == brake_id:
				brake_id = -1
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
	if panel == "house":
		_panel_press(p)
		return
	if _btn_house().has_point(p):
		panel = "house"
		return
	if _btn_tp().has_point(p):
		_teleport(Vector3(0, 0.5, 6) if _in_park() else Vector3(80, 0.5, 6))
		return
	if _btn_swap().has_point(p):
		state = "select"
		return
	if skating and p.distance_to(_btn_brake()) < 75:
		brake_id = idx
		return
	if skating and p.distance_to(_btn_trick()) < 75:
		_do_trick()
		return
	if skating and p.distance_to(_btn_cycle()) < 65:
		trick_sel = (trick_sel + 1) % maxi(tricks_open.size(), 1)
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
	brake_id = -1
	_reset_trick()
	player.floor_stop_on_slope = not skating
	if board != null:
		board.visible = skating
	cam.position.z = 5.5 if skating else 4.5
	cur_anim = ""

func _do_jump() -> void:
	if player.is_on_floor():
		vel.y = JUMP_V * (1.15 if skating else 1.0)
		_play("jump_start")

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
		if brake_id != -1:
			skate_speed = move_toward(skate_speed, 0.0, 18.0 * d)
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
	if skating and player.is_on_floor():
		stats["dist"] = float(stats["dist"]) + Vector2(vel.x, vel.z).length() * d
	if player.is_on_floor() and not was_on_floor:
		land_t = 0.25
		_on_land()
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
	toast_t = maxf(0.0, toast_t - d)
	for i in range(coin_nodes.size()):
		var c: Node3D = coin_nodes[i]
		if c.visible:
			c.rotation.y += 2.5 * d
			if state == "play" and player != null and c.global_position.distance_to(player.global_position + Vector3(0, 0.9, 0)) < 1.1:
				c.visible = false
				coin_respawn[i] = 45.0
				coins += 10
				stats["coins_got"] = int(stats["coins_got"]) + 1
				_save()
		else:
			coin_respawn[i] = float(coin_respawn[i]) - d
			if float(coin_respawn[i]) <= 0.0:
				c.visible = true
	if state == "play":
		if int(stats["park"]) == 0 and _in_park():
			stats["park"] = 1
		_check_quest()
	if player == null or model == null:
		return
	visual.rotation.y = lerp_angle(visual.rotation.y, heading, minf(1.0, 18.0 * d))
	var lift := SKATE_LIFT if skating else 0.0
	model.position.y = lerpf(model.position.y, MODEL_SCALE + lift, minf(1.0, 15.0 * d))
	if board != null and skating:
		if trick_active:
			trick_t = maxf(0.0, trick_t - d)
			var pr := (1.0 - trick_t / trick_dur) * TAU
			board.rotation = Vector3.ZERO
			match str(trick_def["id"]):
				"kickflip":
					board.rotation.z = pr
				"heelflip":
					board.rotation.z = -pr
				"shuvit":
					board.rotation.y = pr
				"flip360":
					board.rotation.z = pr
					board.rotation.y = pr
			if trick_t <= 0.0:
				trick_active = false
				trick_pending = int(trick_def["pts"])
				board.rotation = Vector3.ZERO
		else:
			board.rotation = Vector3.ZERO
	cam_pivot.rotation = Vector3(pitch, yaw, 0)
	var ip: Vector3 = prev_pos.lerp(cur_pos, Engine.get_physics_interpolation_fraction())
	visual.global_position = ip
	var target: Vector3 = ip + Vector3(0, 1.5, 0)
	cam_pivot.global_position = cam_pivot.global_position.lerp(target, minf(1.0, 12.0 * d))
	hud.queue_redraw()
