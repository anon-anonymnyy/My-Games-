extends Node3D
# «Саша на борде» — сборка 2 «Первые деньги»

const WALK := 5.0
const RUN := 8.5
const SKATE_MAX := 14.0
const GRAVITY := 24.0
const JUMP_V := 8.0
const STICK_R := 90.0
const MODEL_SCALE := 1.05
const SKATE_LIFT := 0.12
const LOOPING := ["idle", "walk", "run", "fall", "skate_ride", "skate_push", "skate_stand"]
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
	{"name": "Клумбы у дома", "cost": 600, "inc": 60},
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
var mount_t := 0.0
var push_t := 0.0
var push_cd := 2.5
var boost := 0.0
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
var vis_h := 0.0
var vis_up := Vector3.UP
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
	_build_story()
	_build_audio()
	_set_step(story)
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
		story = int(data.get("story", 0))
		snd_on = bool(data.get("snd", true))
		gear = data.get("gear", [])
		var st = data.get("stats", {})
		if typeof(st) == TYPE_DICTIONARY:
			for k in stats.keys():
				stats[k] = st.get(k, stats[k])

func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"coins": coins, "streak": streak, "last_day": last_day, "char": char_id, "tricks_open": tricks_open, "quest_i": quest_i, "owned": owned, "last_collect": last_collect, "story": story, "snd": snd_on, "gear": gear, "stats": stats}))

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
	_grandma_house()
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
		if i != 3 and i != 4 and i != -3:
			_house(i * 22.0, -9.0, 10, 7, 4.2 + (i % 2) * 0.8, wc[absi(i) % 4], Color(0.35, 0.25, 0.25), 1.0)
		if i != -3 and i != -2:
			_house(i * 22.0 + 6, 36.0, 10, 7, 5.0, wc[(absi(i) + 1) % 4], Color(0.3, 0.3, 0.38), -1.0)
	_build_market()
	_build_shop()
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

func _grandma_house() -> void:
	var path := "res://house_sasha.glb"
	var sc: PackedScene = null
	if ResourceLoader.exists(path):
		sc = load(path)
	if sc == null:
		var gr := _house(-4, -9, 11, 7, 4.5, Color(0.93, 0.85, 0.65), Color(0.6, 0.2, 0.15), 1.0)
		roof_mat = gr.material_override as StandardMaterial3D
		return
	var m: Node3D = sc.instantiate()
	m.scale = Vector3.ONE * 9.5
	m.rotation.y = PI / 2.0
	m.position = Vector3(-4, 0, -7.65)
	add_child(m)
	var sb := StaticBody3D.new()
	sb.position = Vector3(-4, 4.25, -8.4)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(8.8, 8.5, 7.1)
	cs.shape = sh
	sb.add_child(cs)
	add_child(sb)

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
	cam_pivot.global_position = p + Vector3(0, 1.7, 0)

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
	player.floor_max_angle = deg_to_rad(50.0)
	player.position = Vector3(0, 0.1, 6)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.33
	cap.height = 2.0
	cs.shape = cap
	cs.position = Vector3(0, 1.0, 0)
	player.add_child(cs)
	add_child(player)
	visual = Node3D.new()
	visual.top_level = true
	player.add_child(visual)
	prev_pos = player.position
	cur_pos = player.position
	var bscene: PackedScene = load("res://skateboard2.glb")
	if bscene != null:
		board = bscene.instantiate()
		board.scale = Vector3.ONE * 1.55
		board.visible = false
		visual.add_child(board)
	cam_pivot = Node3D.new()
	add_child(cam_pivot)
	cam = Camera3D.new()
	cam.position = Vector3(0, 0, 2.7)
	cam.fov = 70
	cam.current = true
	cam_pivot.add_child(cam)
	cam_pivot.global_position = player.global_position + Vector3(0, 1.7, 0)
	yaw = PI

func _spawn_model(id: String) -> void:
	if model != null:
		model.queue_free()
		model = null
		anim = null
	char_id = id
	var path := "res://sasha_boy.glb" if id == "boy" else "res://sasha_girl.glb"
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

func _attach_cap(id: String) -> void:
	var skel := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		return
	var bi := skel.find_bone("Head")
	if bi < 0:
		return
	var capscene: PackedScene = load("res://red_cap.glb")
	if capscene == null:
		return
	var att := BoneAttachment3D.new()
	att.bone_name = "Head"
	skel.add_child(att)
	var c: Node3D = capscene.instantiate()
	if id == "boy":
		c.position = Vector3(0.0, 0.12, -0.015)
		c.scale = Vector3(0.74, 0.70, 0.74)
	else:
		c.position = Vector3(0.0, 0.10, -0.015)
		c.scale = Vector3(0.72, 0.60, 0.72)
	c.rotation_degrees = Vector3(6.0, 0.0, 0.0)
	att.add_child(c)

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
	mini = Control.new()
	mini.size = Vector2(MM_SIZE, MM_SIZE)
	mini.clip_contents = true
	mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(mini)
	mini.draw.connect(_mini_draw)

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
	_text(_district(), Vector2(22, 100), 24, Color(1, 1, 1, 0.8))
	_text("FPS %d" % Engine.get_frames_per_second(), Vector2(22, 130), 20, Color(1, 1, 1, 0.6))
	hud.draw_rect(_btn_swap(), Color(0, 0, 0, 0.45), true)
	_text_c("Сменить", _btn_swap().get_center(), 26)
	hud.draw_rect(_btn_snd(), Color(0, 0, 0, 0.45), true)
	_text_c("Звук" if snd_on else "Тихо", _btn_snd().get_center(), 24, Color.WHITE if snd_on else Color(1, 0.6, 0.6))
	hud.draw_rect(_btn_house(), Color(0.45, 0.3, 0.1, 0.8), true)
	hud.draw_rect(_btn_house(), Color(1, 1, 1, 0.6), false, 2.0)
	_text_c("Дом  +%d ₽" % _pending_income(), _btn_house().get_center(), 24)
	hud.draw_rect(_btn_tp(), Color(0.15, 0.35, 0.3, 0.8), true)
	hud.draw_rect(_btn_tp(), Color(1, 1, 1, 0.6), false, 2.0)
	_text_c("→ " + str((TP[tp_i % TP.size()] as Array)[0]), _btn_tp().get_center(), 22)
	hud.draw_rect(Rect2(20, 148, 340, 100), Color(0, 0, 0, 0.45), true)
	_text("ЗАДАНИЕ", Vector2(30, 170), 16, Color(1, 0.85, 0.3))
	hud.draw_multiline_string(font, Vector2(30, 194), _obj_text(), HORIZONTAL_ALIGNMENT_LEFT, 320.0, 20, 3, Color.WHITE)
	_text("Доп.: " + _quest_text().replace("Задание: ", ""), Vector2(22, 268), 16, Color(1, 0.95, 0.6, 0.8))
	if toast_t > 0.0:
		var tr := Rect2(s.x * 0.5 - 260, 160, 520, 64)
		hud.draw_rect(tr, Color(0.1, 0.4, 0.15, 0.88), true)
		_text_c(toast, tr.get_center(), 22)
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
		_text_c("след.: " + _trick_name(), _btn_trick() + Vector2(0, 74), 16, Color(1, 1, 1, 0.8))
	if act_id != "":
		_btn_draw(_btn_act(), 56, Color(0.2, 0.6, 0.3, 0.8))
		_text_c(act_label, _btn_act(), 22)
	if panel == "house":
		_draw_house_panel(s)
	if panel == "shop":
		_draw_shop_panel(s)
	if dlg.size() > 0:
		_draw_dialog(s)
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
	if story >= 7:
		t += 50
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
				_sfx("good")
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
	elif _has(1) and roof_mat == null and not upgrade_nodes.has(1):
		upgrade_nodes[1] = true
		var fc := [Color(0.9, 0.3, 0.35), Color(0.95, 0.8, 0.2), Color(0.85, 0.4, 0.8), Color(0.95, 0.6, 0.2)]
		for k in range(7):
			_box(Vector3(-8.0 + k * 1.3, 0.15, -2.2), Vector3(1.0, 0.3, 0.6), fc[k % 4], false)
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
		_sfx("good")
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
	trick_sel = (trick_sel + 1) % tricks_open.size()
	trick_active = true
	trick_dur = 0.5
	trick_t = trick_dur

func _reset_trick() -> void:
	trick_active = false
	trick_pending = 0
	if board != null:
		board.rotation = Vector3.ZERO

func _on_land() -> void:
	_sfx("land")
	if trick_active and trick_t < 0.25:
		trick_pending = int(trick_def["pts"])
	if trick_pending > 0 and "grip" in gear:
		trick_pending = int(float(trick_pending) * 1.2)
	if trick_pending > 0:
		stats["tricks"] = int(stats["tricks"]) + 1
		stats["score"] = int(stats["score"]) + trick_pending
		var bonus := maxi(trick_pending / 50, 1)
		coins += bonus
		_toast("%s! +%d очков, +%d ₽" % [trick_def["name"], trick_pending, bonus])
		_sfx("good")
		_save()
	elif trick_active:
		_toast("Не докрутил трюк")
	_reset_trick()

# ---------------- сюжет, NPC, диалоги (сборка 2) ----------------
const LIGHT_COST := 500
const MM_SIZE := 170.0
const MM_SCALE := 1.3
const L_PTS := [Vector3(-60, 0, 13), Vector3(-42, 0, 27), Vector3(-26, 0, 13), Vector3(-10, 0, 27), Vector3(8, 0, 13)]
const CAR_POS := Vector3(-60, 0, 35)
const DOOR_POS := Vector3(-4, 0, -3.0)
const THUG_WP := [Vector3(-47, 0.04, 35.5), Vector3(-47, 0.04, 31.0), Vector3(-38, 0.04, 22.0), Vector3(0, 0.04, 22.0), Vector3(40, 0.04, 22.0), Vector3(40, 0.04, 17.0), Vector3(0, 0.04, 17.0), Vector3(-40, 0.04, 17.0), Vector3(-47, 0.04, 31.0)]
const TP := [["Двор", Vector3(0, 0.5, 6)], ["Рынок", Vector3(-50, 0.5, 31)], ["Скейт-парк", Vector3(80, 0.5, 6)]]
const NPC_DEF := {
	"lyuda": {"file": "npc_granny", "name": "Тётя Люда", "pos": Vector3(-22, 0, -3), "ry": 0.0},
	"gosha": {"file": "npc_shopkeeper", "name": "Дядя Гоша", "pos": Vector3(-50, 0, 41.6), "ry": PI},
	"kesha": {"file": "npc_mechanic", "name": "Кеша", "pos": Vector3(-66, 0, -3), "ry": 0.0}}
const SHOP := [
	{"id": "wheels", "name": "Колёса", "desc": "+1 к максимальной скорости", "cost": 300},
	{"id": "bearings", "name": "Подшипники", "desc": "+1,5 к максимальной скорости", "cost": 700},
	{"id": "grip", "name": "Грип-лента", "desc": "+20% очков за трюки", "cost": 500}]
const OBJ := [
	"Поговори с тётей Людой (она стоит слева от двора)",
	"Найди дядю Гошу на рынке (кнопка «→ Рынок» вверху)",
	"Листовки: разнеси по адресам (%d/5)",
	"Вернись к дяде Гоше за новой работой",
	"Горячая доставка: отвези пирожки тёте Люде! Осталось %d с",
	"Помой машину дяди Гоши на рынке (%d/14)",
	"Заплати за свет: %d ₽ у двери бабушкиного дома",
	"Сходи к Кеше в скейт-шоп (дом далеко слева)",
	"Купи колёса у Кеши (300 ₽)",
	"Беги к дяде Гоше: на рынке беда!",
	"Догони вора с кассой! Осталось %d с",
	"Вернись к дяде Гоше с кассой",
	"Сборка 2 пройдена! Копи деньги, улучшай дом, катайся"]
const DLG := {
	"prolog": [
		["Саша", "Щёлк, щёлк… Света нет. Холодильник молчит, чайник молчит. Хоть кто-то в этом доме отдыхает."],
		["Тётя Люда", "Доброе утро, Саша! Свет вам отключили за долг, милый. Бабушка в санатории, так что разбираться тебе."],
		["Саша", "Значит, срочно нужны деньги. Хоть какая-нибудь подработка."],
		["Тётя Люда", "Иди на рынок к дяде Гоше. Мужик добрый, работу найдёт. Рынок слева по улице, или нажми кнопку «→ Рынок» вверху."],
		["Тётя Люда", "И бери скейт. На нём ты быстрее автобуса."]],
	"gosha1": [
		["Дядя Гоша", "О, Саша! Чего такой хмурый? Хмурый у нас другой, он по рынку ходит, лучше с ним не пересекаться."],
		["Саша", "Дядя Гоша, у нас свет отключили. Нужны деньги, любые честные."],
		["Дядя Гоша", "Честные у меня есть. Бери листовки моей лавки и разнеси по пяти адресам. Они отмечены на мини-карте жёлтым."],
		["Дядя Гоша", "На скейте быстрее. Только почтовые ящики не сбивай!"]],
	"gosha2": [
		["Дядя Гоша", "Ровно пять! Ни одной не выкинул в урну, уважаю. Деньги получил?"],
		["Дядя Гоша", "Теперь горячая работа, в прямом смысле. Отвези пирожки тёте Люде, пока не остыли. У тебя 90 секунд!"]],
	"deliver_ok": [
		["Тётя Люда", "Пирожки ещё горячие! Саша, ты быстрее любого курьера. Вот тебе за доставку."],
		["Тётя Люда", "А ещё у дяди Гоши на рынке машина вся в грязи. Он давно просит помыть. Сходи, заработаешь."]],
	"wash_ok": [
		["Саша", "Блестит как новая! Теперь можно думать про свет."],
		["Саша", "Нужно накопить на оплату и идти к двери бабушкиного дома. Монеты на улице тоже помогут."]],
	"light_ok": [
		["Саша", "Щёлк! Свет! Чайник! Холодильник! Никогда так не радовался электричеству."],
		["Саша", "Дом теперь приносит немного денег. А скейт совсем облысел: колёса стёрты. Надо к Кеше."]],
	"kesha1": [
		["Кеша", "О, Саша! Это что у тебя? Колёса стёрлись, это не доска, а санки."],
		["Саша", "Денег мало, но колёса нужны."],
		["Кеша", "Колёса стоят 300 ₽. Подшипники и грип позже, когда разбогатеешь. Заходи, вот прайс."]],
	"kesha_hi": [
		["Кеша", "Заходи! Смотри, что есть."]],
	"kesha_ok": [
		["Кеша", "Другое дело! Теперь едет как по маслу. Только в рыночные лавки не врезайся."],
		["Саша", "Спасибо, Кеша! Как раз надо к дяде Гоше."]],
	"gosha3": [
		["Дядя Гоша", "Саша! Беда! Хмурый с подручным утащили мою кассу и бегут по улице!"],
		["Дядя Гоша", "Драться не надо, ты у нас интеллигент. Просто догони! Скейт у тебя теперь отличный."]],
	"thug_caught": [
		["Подручный", "Ай! Ладно-ладно, забирай свою кассу! Только Хмурому не говори!"],
		["Саша", "Передам привет. Кассу несу дяде Гоше."]],
	"gosha4": [
		["Дядя Гоша", "Касса на месте! Саша, ты настоящая находка. Вот премия."],
		["Дядя Гоша", "Хулиганов гонять хорошо, но надо уметь и постоять за себя. Тренер Пак как раз ищет учеников."],
		["", "Зал тренера Пака и новые задания появятся в следующем обновлении. Пока катайся, копи деньги и улучшай дом."]],
	"hi_gosha": [
		["Дядя Гоша", "Заходи, Саша! Работы пока нет, но скоро будет. Рынок любит расторопных."]],
	"hi_lyuda": [
		["Тётя Люда", "Здравствуй, Саша! Кушать хочешь? Шучу, у тебя же скейт, ты на нём всё время едешь."]]}

var story := 0
var sp := 0
var step_t := 0.0
var gear: Array = []
var dlg: Array = []
var dlg_i := 0
var dlg_after: Callable = Callable()
var npcs: Dictionary = {}
var tgt_node: MeshInstance3D
var car_mat: StandardMaterial3D
var lamp_built := false
var act_id := ""
var act_label := ""
var mini: Control
var tp_i := 1
var thug: Node3D
var thug_wp := 1

func _smax() -> float:
	var m := SKATE_MAX
	if "wheels" in gear:
		m += 1.0
	if "bearings" in gear:
		m += 1.5
	return m

func _label(t: String, pos: Vector3, fs: int, c: Color, px := 0.012) -> void:
	var lb := Label3D.new()
	lb.text = t
	lb.font_size = fs
	lb.pixel_size = px
	lb.position = pos
	lb.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	lb.modulate = c
	lb.outline_modulate = Color(0.1, 0.1, 0.1)
	add_child(lb)

func _glow_box(pos: Vector3, size: Vector3, c: Color) -> void:
	var b := _box(pos, size, c, false)
	var m := (b.get_child(0) as MeshInstance3D).material_override as StandardMaterial3D
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 1.2

func _build_market() -> void:
	_box(Vector3(-50, 0.03, 44), Vector3(40, 0.06, 28), Color(0.8, 0.76, 0.66), false)
	_box(Vector3(-58, 2.0, 31.5), Vector3(0.3, 4.0, 0.3), Color(0.35, 0.25, 0.2), false)
	_box(Vector3(-42, 2.0, 31.5), Vector3(0.3, 4.0, 0.3), Color(0.35, 0.25, 0.2), false)
	_box(Vector3(-50, 4.0, 31.5), Vector3(16.6, 0.3, 0.3), Color(0.35, 0.25, 0.2), false)
	_label("РЫНОК", Vector3(-50, 5.2, 31.5), 160, Color(1, 0.85, 0.2))
	var awn := [Color(0.85, 0.25, 0.2), Color(0.2, 0.55, 0.8), Color(0.9, 0.7, 0.15), Color(0.3, 0.65, 0.35), Color(0.7, 0.3, 0.6)]
	var xs := [-64.0, -57.0, -50.0, -43.0, -36.0]
	for k in range(5):
		var x: float = xs[k]
		_box(Vector3(x, 0.5, 40), Vector3(3.2, 1.0, 1.2), Color(0.6, 0.45, 0.3))
		_box(Vector3(x - 1.6, 1.4, 41.8), Vector3(0.12, 2.8, 0.12), Color(0.4, 0.3, 0.2), false)
		_box(Vector3(x + 1.6, 1.4, 41.8), Vector3(0.12, 2.8, 0.12), Color(0.4, 0.3, 0.2), false)
		_box(Vector3(x, 2.85, 40.6), Vector3(3.8, 0.12, 2.6), awn[k], false, Vector3(-0.12, 0, 0))
		for j in range(3):
			_box(Vector3(x - 1.0 + j, 1.15, 40), Vector3(0.4, 0.3, 0.4), Color.from_hsv(0.12 * float(j + k), 0.6, 0.9), false)
	_label("ЛАВКА У ГОШИ", Vector3(-50, 3.5, 39.0), 110, Color(1, 1, 1), 0.009)
	for cp in [Vector3(-68, 0.4, 50), Vector3(-66.5, 0.4, 50.4), Vector3(-67.2, 1.2, 50.2), Vector3(-33, 0.4, 52), Vector3(-34.4, 0.4, 51.6)]:
		_box(cp, Vector3(1.0, 0.8, 1.0), Color(0.62, 0.48, 0.3))
	# машина дяди Гоши
	car_mat = _mat(Color(0.38, 0.3, 0.22), 0.6)
	var body := _box(CAR_POS + Vector3(0, 0.65, 0), Vector3(4.2, 0.8, 1.9), Color(0.38, 0.3, 0.22))
	(body.get_child(0) as MeshInstance3D).material_override = car_mat
	var cab := _box(CAR_POS + Vector3(-0.2, 1.4, 0), Vector3(2.3, 0.7, 1.7), Color(0.4, 0.5, 0.6), false)
	(cab.get_child(0) as MeshInstance3D).material_override = car_mat
	for wx in [-1.3, 1.3]:
		for wz in [-0.95, 0.95]:
			_box(CAR_POS + Vector3(wx, 0.3, wz), Vector3(0.7, 0.6, 0.25), Color(0.1, 0.1, 0.1), false)

func _build_shop() -> void:
	_house(-66, -9, 10, 7, 4.5, Color(0.3, 0.35, 0.5), Color(0.2, 0.2, 0.25), 1.0)
	_label("СКЕЙТ-ШОП КЕШИ", Vector3(-66, 3.7, -5.3), 120, Color(1, 0.85, 0.2), 0.009)
	var bc := [Color(0.85, 0.25, 0.2), Color(0.2, 0.6, 0.85), Color(0.9, 0.7, 0.15), Color(0.3, 0.7, 0.4)]
	for k in range(4):
		_box(Vector3(-70.2 + k * 1.1, 1.6, -5.4), Vector3(0.45, 1.5, 0.06), bc[k], false)

func _build_story() -> void:
	for id in NPC_DEF.keys():
		var def: Dictionary = NPC_DEF[id]
		var n := _spawn_npc(str(def["file"]), str(def["name"]), def["pos"], float(def["ry"]), true)
		var an := n.find_child("AnimationPlayer", true, false) as AnimationPlayer
		npcs[id] = {"node": n, "anim": an, "ry": float(def["ry"])}
	for p in L_PTS:
		_box(p + Vector3(0, 0.45, 0), Vector3(0.12, 0.9, 0.12), Color(0.3, 0.3, 0.35), false)
		_box(p + Vector3(0, 1.0, 0), Vector3(0.6, 0.4, 0.4), Color(0.2, 0.4, 0.85), false)
	tgt_node = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.7
	cm.bottom_radius = 0.7
	cm.height = 12.0
	tgt_node.mesh = cm
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(1, 0.85, 0.1, 0.3)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	tgt_node.material_override = bm
	tgt_node.visible = false
	add_child(tgt_node)

func _spawn_npc(file: String, nm: String, pos: Vector3, ry: float, solid: bool) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = ry
	add_child(n)
	var path := "res://%s.glb" % file
	var sc: PackedScene = null
	if ResourceLoader.exists(path):
		sc = load(path)
	if sc != null:
		var m: Node3D = sc.instantiate()
		m.scale = Vector3.ONE * MODEL_SCALE
		m.position = Vector3(0, MODEL_SCALE, 0)
		n.add_child(m)
		var an := m.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if an != null:
			for a in an.get_animation_list():
				an.get_animation(a).loop_mode = Animation.LOOP_LINEAR if (a in LOOPING) else Animation.LOOP_NONE
			if an.has_animation("idle"):
				an.play("idle")
	else:
		var pm := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.35
		cap.height = 1.8
		pm.mesh = cap
		pm.material_override = _mat(Color(0.8, 0.5, 0.3))
		pm.position = Vector3(0, 0.9, 0)
		n.add_child(pm)
	if solid:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := CapsuleShape3D.new()
		sh.radius = 0.4
		sh.height = 1.9
		cs.shape = sh
		cs.position = Vector3(0, 0.95, 0)
		sb.add_child(cs)
		n.add_child(sb)
	var lb := Label3D.new()
	lb.text = nm
	lb.font_size = 64
	lb.pixel_size = 0.006
	lb.position = Vector3(0, 2.4, 0)
	lb.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	lb.outline_modulate = Color(0.1, 0.1, 0.1)
	n.add_child(lb)
	return n

func _npc_pos(id: String) -> Vector3:
	return (NPC_DEF[id] as Dictionary)["pos"]

func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _spawn_thug() -> void:
	if thug != null:
		thug.queue_free()
	thug = _spawn_npc("npc_thug", "Подручный", THUG_WP[0], 0.0, false)
	thug_wp = 1
	var an := thug.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if an != null and an.has_animation("run"):
		an.play("run")

func _thug_move(d: float) -> void:
	var wp: Vector3 = THUG_WP[thug_wp]
	var dv := wp - thug.position
	dv.y = 0.0
	if dv.length() < 0.6:
		thug_wp = (thug_wp + 1) % THUG_WP.size()
		if thug_wp == 0:
			thug_wp = 1
		return
	thug.position += dv.normalized() * 6.5 * d
	thug.rotation.y = lerp_angle(thug.rotation.y, atan2(dv.x, dv.z), minf(1.0, 10.0 * d))

func _set_step(i: int) -> void:
	story = i
	sp = 0
	step_t = 0.0
	if i == 4:
		step_t = 90.0
	if i == 10:
		step_t = 80.0
		_spawn_thug()
	elif thug != null:
		thug.queue_free()
		thug = null
	_apply_story_vis()
	_save()

func _update_car() -> void:
	if car_mat == null:
		return
	var t := 0.0
	if story > 5:
		t = 1.0
	elif story == 5:
		t = clampf(float(sp) / 14.0, 0.0, 1.0)
	car_mat.albedo_color = Color(0.38, 0.3, 0.22).lerp(Color(0.2, 0.5, 0.85), t)

func _apply_story_vis() -> void:
	_update_car()
	if story >= 7 and not lamp_built:
		lamp_built = true
		_box(Vector3(3.5, 1.4, -3.0), Vector3(0.12, 2.8, 0.12), Color(0.25, 0.25, 0.3), false)
		_glow_box(Vector3(3.5, 2.9, -3.0), Vector3(0.5, 0.4, 0.5), Color(1, 0.95, 0.6))

func _story_target() -> Variant:
	match story:
		0, 4:
			return _npc_pos("lyuda")
		1, 3, 9, 11:
			return _npc_pos("gosha")
		2:
			return L_PTS[mini(sp, L_PTS.size() - 1)]
		5:
			return CAR_POS
		6:
			return DOOR_POS
		7, 8:
			return _npc_pos("kesha")
		10:
			if thug != null:
				return thug.position
	return null

func _obj_text() -> String:
	var t: String = OBJ[mini(story, OBJ.size() - 1)]
	match story:
		2, 5:
			return t % [sp]
		4, 10:
			return t % [int(ceil(step_t))]
		6:
			return t % [LIGHT_COST]
	return t

func _reward(n: int, msg: String) -> void:
	coins += n
	_toast("%s +%d ₽" % [msg, n])
	_sfx("good")
	_save()

func _start_dlg(key: String, after := Callable()) -> void:
	dlg = (DLG[key] as Array).duplicate()
	dlg_i = 0
	dlg_after = after
	stick_id = -1
	stick_vec = Vector2.ZERO

func _dlg_next() -> void:
	dlg_i += 1
	if dlg_i >= dlg.size():
		dlg = []
		var cb := dlg_after
		dlg_after = Callable()
		if cb.is_valid():
			cb.call()

func _talk(id: String) -> void:
	if story == 0 and id == "lyuda":
		_set_step(1)
		_start_dlg("prolog")
	elif story == 1 and id == "gosha":
		_set_step(2)
		_start_dlg("gosha1")
	elif story == 3 and id == "gosha":
		_set_step(4)
		_start_dlg("gosha2")
	elif story == 7 and id == "kesha":
		_set_step(8)
		_start_dlg("kesha1", func(): panel = "shop")
	elif story == 9 and id == "gosha":
		_set_step(10)
		_start_dlg("gosha3")
	elif story == 11 and id == "gosha":
		_reward(300, "Премия от дяди Гоши!")
		_set_step(12)
		_start_dlg("gosha4")
	elif id == "kesha":
		_start_dlg("kesha_hi", func(): panel = "shop")
	else:
		_start_dlg("hi_" + id)

func _act_update() -> void:
	act_id = ""
	act_label = ""
	if state != "play" or dlg.size() > 0 or panel != "" or popup or player == null:
		return
	var pp := player.global_position
	if story == 5 and _flat_dist(pp, CAR_POS) < 4.5:
		act_id = "wash"
		act_label = "Мыть"
	elif story == 6 and _flat_dist(pp, DOOR_POS) < 3.5:
		act_id = "pay"
		act_label = "Свет"
	else:
		for id in npcs.keys():
			var n: Node3D = npcs[id]["node"]
			if _flat_dist(pp, n.global_position) < 4.0:
				act_id = "talk:" + str(id)
				act_label = "Говорить"
				break

func _act_press() -> void:
	if act_id == "wash":
		sp += 1
		_update_car()
		if sp >= 14:
			_reward(300, "Машина блестит!")
			_set_step(6)
			_start_dlg("wash_ok")
	elif act_id == "pay":
		if coins >= LIGHT_COST:
			coins -= LIGHT_COST
			_set_step(7)
			_start_dlg("light_ok")
		else:
			_toast("Не хватает: нужно %d ₽" % LIGHT_COST)
	elif act_id.begins_with("talk:"):
		_talk(act_id.substr(5))

func _story_process(d: float) -> void:
	if dlg.size() > 0 or player == null:
		return
	var pp := player.global_position
	if story == 2:
		var tp: Vector3 = L_PTS[sp]
		if _flat_dist(pp, tp) < 3.0:
			sp += 1
			if sp >= L_PTS.size():
				_reward(150, "Листовки розданы!")
				_set_step(3)
			else:
				_toast("Листовка доставлена: %d/%d" % [sp, L_PTS.size()])
	elif story == 4:
		step_t -= d
		if _flat_dist(pp, _npc_pos("lyuda")) < 4.5:
			_reward(250, "Доставка выполнена!")
			_set_step(5)
			_start_dlg("deliver_ok")
		elif step_t <= 0.0:
			step_t = 90.0
			_toast("Пирожки остыли! Время вышло, попробуй ещё раз")
	elif story == 8 and "wheels" in gear:
		_set_step(9)
		_start_dlg("kesha_ok")
	elif story == 10 and thug != null:
		step_t -= d
		_thug_move(d)
		if _flat_dist(pp, thug.position) < 3.0:
			_reward(500, "Вор пойман!")
			_set_step(11)
			_start_dlg("thug_caught")
		elif step_t <= 0.0:
			step_t = 80.0
			thug.position = THUG_WP[0]
			thug_wp = 1
			_toast("Вор ушёл! Он вернулся к рынку, попробуй ещё раз")

func _npcs_update(d: float) -> void:
	if player == null:
		return
	var pp := player.global_position
	for id in npcs.keys():
		var e: Dictionary = npcs[id]
		var n: Node3D = e["node"]
		var dist := _flat_dist(pp, n.global_position)
		var vis := dist < 90.0
		if n.visible != vis:
			n.visible = vis
			var an: AnimationPlayer = e["anim"]
			if an != null:
				an.active = vis
		if vis and dist < 7.0:
			n.rotation.y = lerp_angle(n.rotation.y, atan2(pp.x - n.global_position.x, pp.z - n.global_position.z), minf(1.0, 5.0 * d))
		elif vis:
			n.rotation.y = lerp_angle(n.rotation.y, float(e["ry"]), minf(1.0, 3.0 * d))
	var t: Variant = _story_target()
	tgt_node.visible = t != null
	if t != null:
		tgt_node.global_position = (t as Vector3) + Vector3(0, 6.0, 0)

func _district() -> String:
	if player == null:
		return "Липовая"
	var p := player.global_position
	if p.x > 52.0:
		return "Ромашка"
	if p.x < -28.0 and p.z > 30.0:
		return "Рынок"
	return "Липовая"

# ---------------- мини-карта ----------------
func _mm(p: Vector3) -> Vector2:
	var rel := p - player.global_position
	var fw := Vector3(-sin(yaw), 0, -cos(yaw))
	var rt := Vector3(cos(yaw), 0, -sin(yaw))
	return Vector2(MM_SIZE * 0.5, MM_SIZE * 0.5) + Vector2(rel.dot(rt), -rel.dot(fw)) * MM_SCALE

func _mm_rect(x0: float, z0: float, x1: float, z1: float, c: Color) -> void:
	mini.draw_colored_polygon(PackedVector2Array([_mm(Vector3(x0, 0, z0)), _mm(Vector3(x1, 0, z0)), _mm(Vector3(x1, 0, z1)), _mm(Vector3(x0, 0, z1))]), c)

func _mini_draw() -> void:
	if player == null or state != "play":
		return
	mini.draw_rect(Rect2(0, 0, MM_SIZE, MM_SIZE), Color(0.3, 0.5, 0.28))
	_mm_rect(-100, 10, 140, 14, Color(0.72, 0.72, 0.74))
	_mm_rect(-100, 26, 140, 30, Color(0.72, 0.72, 0.74))
	_mm_rect(-100, 15, 140, 25, Color(0.25, 0.25, 0.28))
	_mm_rect(-15, -13, 15, 10, Color(0.45, 0.62, 0.4))
	_mm_rect(-9.5, -12.5, 1.5, -5.5, Color(0.8, 0.45, 0.35))
	_mm_rect(-71, -12.5, -61, -5.5, Color(0.3, 0.35, 0.5))
	_mm_rect(-70, 30, -30, 58, Color(0.85, 0.8, 0.65))
	_mm_rect(54, -31, 106, 11, Color(0.6, 0.6, 0.66))
	for id in npcs.keys():
		var n: Node3D = npcs[id]["node"]
		mini.draw_circle(_mm(n.global_position), 4.0, Color(1, 0.6, 0.2))
	var c := Vector2(MM_SIZE * 0.5, MM_SIZE * 0.5)
	var t: Variant = _story_target()
	if t != null:
		var tp := _mm(t as Vector3)
		var dv := tp - c
		var lim := MM_SIZE * 0.5 - 12.0
		var m := maxf(absf(dv.x), absf(dv.y))
		if m > lim:
			dv *= lim / m
		tp = c + dv
		mini.draw_circle(tp, 8.0, Color(0.1, 0.1, 0.1))
		mini.draw_circle(tp, 6.0, Color(1, 0.85, 0.1))
	mini.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -10), c + Vector2(-7, 7), c + Vector2(0, 3), c + Vector2(7, 7)]), Color(1, 1, 1))
	mini.draw_rect(Rect2(0, 0, MM_SIZE, MM_SIZE), Color(1, 1, 1, 0.8), false, 3.0)

# ---------------- окна: диалог и магазин ----------------
func _draw_dialog(s: Vector2) -> void:
	var r := _dlg_rect()
	hud.draw_rect(r, Color(0.08, 0.1, 0.18, 0.92), true)
	hud.draw_rect(r, Color(1, 0.85, 0.3), false, 3.0)
	var line: Array = dlg[dlg_i]
	var who := str(line[0])
	var col := Color(0.6, 0.85, 1) if who == "Саша" else Color(1, 0.85, 0.35)
	if who != "":
		_text(who, Vector2(r.position.x + 24, r.position.y + 40), 30, col)
	hud.draw_multiline_string(font, Vector2(r.position.x + 24, r.position.y + 84), str(line[1]), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 48, 26, 4, Color.WHITE)
	hud.draw_rect(_btn_dlg(), Color(0.25, 0.6, 0.3), true)
	hud.draw_rect(_btn_dlg(), Color(1, 1, 1, 0.7), false, 2.0)
	_text_c("Дальше" if dlg_i < dlg.size() - 1 else "Закрыть", _btn_dlg().get_center(), 26)

func _draw_shop_panel(s: Vector2) -> void:
	hud.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.6))
	var pr := _pr()
	hud.draw_rect(pr, Color(0.2, 0.22, 0.32), true)
	hud.draw_rect(pr, Color(1, 0.85, 0.3), false, 4.0)
	_text_c("Скейт-шоп Кеши", Vector2(pr.get_center().x, pr.position.y + 40), 38)
	hud.draw_rect(_pr_close(), Color(0.7, 0.2, 0.2), true)
	_text_c("Закрыть", _pr_close().get_center(), 20)
	_text("У тебя: %d ₽" % coins, Vector2(pr.position.x + 24, pr.position.y + 110), 26, Color(1, 0.9, 0.3))
	for i in range(SHOP.size()):
		var r := _pr_row(i)
		hud.draw_rect(r, Color(0.28, 0.3, 0.45), true)
		var u: Dictionary = SHOP[i]
		_text(str(u["name"]), Vector2(r.position.x + 14, r.position.y + 26), 24)
		_text(str(u["desc"]), Vector2(r.position.x + 14, r.position.y + 50), 18, Color(0.8, 0.85, 1))
		var b := _pr_buy(i)
		if str(u["id"]) in gear:
			hud.draw_rect(b, Color(0.25, 0.25, 0.3), true)
			_text_c("Куплено", b.get_center(), 22)
		else:
			hud.draw_rect(b, Color(0.8, 0.6, 0.1) if coins >= int(u["cost"]) else Color(0.4, 0.35, 0.3), true)
			_text_c("%d ₽" % int(u["cost"]), b.get_center(), 24)

func _shop_press(p: Vector2) -> void:
	if _pr_close().has_point(p) or not _pr().has_point(p):
		panel = ""
		return
	for i in range(SHOP.size()):
		if _pr_buy(i).has_point(p):
			var u: Dictionary = SHOP[i]
			if str(u["id"]) in gear:
				return
			if coins >= int(u["cost"]):
				coins -= int(u["cost"])
				gear.append(str(u["id"]))
				_toast("Куплено: %s" % u["name"])
				_sfx("good")
				_save()
			else:
				_toast("Не хватает ₽")
				_sfx("bad")

func _btn_act() -> Vector2:
	return _vs() - Vector2(130, 410)

# ---------------- звук (всё синтезируется кодом, файлов не нужно) ----------------
const SR := 22050
var snd: Dictionary = {}
var snd_on := true
var sfx_pl: Array = []
var sfx_i := 0
var roll_pl: AudioStreamPlayer
var music_pl: AudioStreamPlayer

func _wav(s: PackedFloat32Array, rate: int, loop := false) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	var b := PackedByteArray()
	b.resize(s.size() * 2)
	for i in range(s.size()):
		b.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32767.0))
	w.data = b
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = s.size()
	return w

func _notes(freqs: Array, note_len: float, vol: float, sq: bool) -> PackedFloat32Array:
	var n := int(note_len * SR)
	var out := PackedFloat32Array()
	out.resize(n * freqs.size())
	for k in range(freqs.size()):
		var f: float = freqs[k]
		for i in range(n):
			var t := float(i) / float(SR)
			var ph := fposmod(f * t, 1.0)
			var w := (1.0 if ph < 0.5 else -1.0) if sq else sin(TAU * ph)
			var env := exp(-4.0 * float(i) / float(n)) * minf(1.0, float(i) / 80.0)
			out[k * n + i] = w * vol * env
	return out

func _sweep(f0: float, f1: float, dur: float, vol: float) -> PackedFloat32Array:
	var n := int(dur * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in range(n):
		var u := float(i) / float(n)
		ph += lerpf(f0, f1, u) / float(SR)
		out[i] = sin(TAU * ph) * vol * (1.0 - u)
	return out

func _noise(dur: float, vol: float, decay: float, lp: float) -> PackedFloat32Array:
	var n := int(dur * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in range(n):
		y += lp * (randf_range(-1.0, 1.0) - y)
		out[i] = y * vol * exp(-decay * float(i) / float(n))
	return out

func _mf(m: float) -> float:
	return 440.0 * pow(2.0, (m - 69.0) / 12.0)

func _make_music() -> AudioStreamWAV:
	var rate := 11025
	var beat := 0.6
	var roots := [48.0, 45.0, 41.0, 43.0]
	var minor := [false, true, false, false]
	var pat := [0, 1, 2, 1, 2, 1, 0, 1]
	var total := int(16.0 * beat * float(rate))
	var out := PackedFloat32Array()
	out.resize(total)
	for ch in range(4):
		var r: float = roots[ch]
		var tri: Array = [0.0, 3.0 if minor[ch] else 4.0, 7.0]
		for b in range(4):
			var bf := _mf(r)
			var start := int((float(ch * 4 + b) * beat) * float(rate))
			var len := int(beat * float(rate))
			for i in range(len):
				var t := float(i) / float(rate)
				var ph := fposmod(bf * t, 1.0)
				var w := 4.0 * absf(ph - 0.5) - 1.0
				out[start + i] += w * 0.22 * exp(-2.5 * float(i) / float(len))
		for e in range(8):
			var mf := _mf(r + 24.0 + float(tri[pat[e]]))
			var start2 := int((float(ch * 4) * beat + float(e) * beat * 0.5) * float(rate))
			var len2 := int(beat * 0.5 * float(rate))
			for i in range(len2):
				var t2 := float(i) / float(rate)
				var w2 := 1.0 if fposmod(mf * t2, 1.0) < 0.5 else -1.0
				out[start2 + i] += w2 * 0.09 * exp(-5.0 * float(i) / float(len2))
	return _wav(out, rate, true)

func _build_audio() -> void:
	snd["coin"] = _wav(_notes([988.0, 1319.0], 0.09, 0.35, true), SR)
	snd["jump"] = _wav(_sweep(260.0, 620.0, 0.16, 0.4), SR)
	snd["land"] = _wav(_noise(0.14, 0.9, 6.0, 0.12), SR)
	snd["click"] = _wav(_notes([1100.0], 0.05, 0.35, true), SR)
	snd["blip"] = _wav(_notes([660.0], 0.06, 0.3, true), SR)
	snd["good"] = _wav(_notes([523.0, 659.0, 784.0, 1047.0], 0.11, 0.35, false), SR)
	snd["push"] = _wav(_noise(0.18, 0.7, 4.0, 0.3), SR)
	snd["bad"] = _wav(_notes([300.0, 220.0], 0.14, 0.35, true), SR)
	for i in range(5):
		var p := AudioStreamPlayer.new()
		p.volume_db = -4.0
		add_child(p)
		sfx_pl.append(p)
	roll_pl = AudioStreamPlayer.new()
	roll_pl.stream = _wav(_noise(1.0, 0.7, 0.0, 0.12), SR, true)
	roll_pl.volume_db = -80.0
	add_child(roll_pl)
	roll_pl.play()
	music_pl = AudioStreamPlayer.new()
	music_pl.stream = _make_music()
	music_pl.volume_db = -15.0
	add_child(music_pl)
	music_pl.play()
	_snd_apply()

func _snd_apply() -> void:
	if music_pl != null:
		music_pl.volume_db = -15.0 if snd_on else -80.0

func _sfx(n: String) -> void:
	if not snd_on or sfx_pl.is_empty() or not snd.has(n):
		return
	var p: AudioStreamPlayer = sfx_pl[sfx_i % sfx_pl.size()]
	sfx_i += 1
	p.stream = snd[n]
	p.play()

func _roll_update() -> void:
	if roll_pl == null:
		return
	var on := snd_on and state == "play" and skating and player != null and player.is_on_floor() and skate_speed > 0.8
	if on:
		roll_pl.volume_db = lerpf(-24.0, -8.0, clampf(skate_speed / _smax(), 0.0, 1.0))
		roll_pl.pitch_scale = 0.7 + skate_speed * 0.04
	else:
		roll_pl.volume_db = -80.0

func _btn_snd() -> Rect2:
	return Rect2(_vs().x - 190 - 120, 20, 100, 60)

func _dlg_rect() -> Rect2:
	var s := _vs()
	return Rect2(s.x * 0.5 - 520, s.y - 250, 1040, 200)

func _btn_dlg() -> Rect2:
	var r := _dlg_rect()
	return Rect2(r.end.x - 220, r.end.y - 66, 200, 50)

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
			_sfx("good")
			_save()
		return
	if dlg.size() > 0:
		if _btn_dlg().has_point(p):
			_sfx("blip")
			_dlg_next()
		return
	if panel == "house":
		_panel_press(p)
		return
	if panel == "shop":
		_shop_press(p)
		return
	if _btn_snd().has_point(p):
		snd_on = not snd_on
		_snd_apply()
		_save()
		_sfx("click")
		return
	if _btn_house().has_point(p):
		panel = "house"
		return
	if _btn_tp().has_point(p):
		var dest: Array = TP[tp_i % TP.size()]
		_teleport(dest[1])
		tp_i += 1
		return
	if _btn_swap().has_point(p):
		state = "select"
		return
	if act_id != "" and p.distance_to(_btn_act()) < 70:
		_sfx("click")
		_act_press()
		return
	if skating and p.distance_to(_btn_brake()) < 75:
		brake_id = idx
		return
	if skating and p.distance_to(_btn_trick()) < 75:
		_do_trick()
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
	player.floor_max_angle = deg_to_rad(88.0 if skating else 50.0)
	player.floor_snap_length = 0.6 if skating else 0.1
	if board != null:
		board.visible = skating
	mount_t = 0.8 if skating else 0.0
	push_t = 0.0
	push_cd = 2.5
	boost = 0.0
	cam.position.z = 3.4 if skating else 2.7
	cur_anim = ""

func _do_jump() -> void:
	if player.is_on_floor():
		vel.y = JUMP_V * (1.15 if skating else 1.0)
		_sfx("jump")
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
	if dlg.size() > 0:
		stick_vec = Vector2.ZERO
		stick_id = -1
	var mag := stick_vec.length()
	if skating and mount_t > 0.0:
		mount_t = maxf(0.0, mount_t - d)
		mag = 0.0
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
		if on_floor:
			var n := player.get_floor_normal()
			var hv := Vector3(vel.x, 0, vel.z)
			if mag > 0.15:
				heading = lerp_angle(heading, atan2(dir.x, dir.z), minf(1.0, 3.0 * d))
			elif hv.length() > 1.5:
				heading = lerp_angle(heading, atan2(hv.x, hv.z), minf(1.0, 4.0 * d))
			var fwd := Vector3(sin(heading), 0, cos(heading))
			var along := hv.dot(fwd)
			var lat := hv - fwd * along
			lat = lat.move_toward(Vector3.ZERO, 14.0 * d)
			var tspd := _smax() * mag * (0.8 + 0.2 * boost)
			if mag > 0.15:
				if along < tspd:
					along = move_toward(along, tspd, 6.0 * d)
				else:
					along = move_toward(along, tspd, 0.7 * d)
			else:
				along = move_toward(along, 0.0, 1.2 * d)
			if brake_id != -1 or dlg.size() > 0:
				along = move_toward(along, 0.0, 18.0 * d)
				lat = lat.move_toward(Vector3.ZERO, 18.0 * d)
			hv = fwd * along + lat
			vel.x = hv.x
			vel.z = hv.z
			if n.y > 0.99:
				if vel.y <= 0.0:
					vel.y = -1.0 if hv.length() > 0.8 else 0.0
			else:
				var g := Vector3(0, -15.0, 0)
				vel += (g - n * g.dot(n)) * d
		else:
			vel.y -= GRAVITY * d
			if mag > 0.15:
				var hv2 := Vector3(vel.x, 0, vel.z)
				var want := dir * minf(_smax() * mag, 8.0)
				if hv2.length() < want.length():
					hv2 = hv2.move_toward(want, 20.0 * d)
					vel.x = hv2.x
					vel.z = hv2.z
	if not skating:
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
		skate_speed = Vector2(vel.x, vel.z).length()
		boost = maxf(0.0, boost - d / 3.5)
		if player.is_on_floor() and mag > 0.15 and mount_t <= 0.0 and not trick_active:
			if push_t > 0.0:
				push_t = maxf(0.0, push_t - d)
			elif skate_speed > 3.0 and skate_speed >= _smax() * mag * 0.7:
				push_cd -= d
				if push_cd <= 0.0:
					push_t = 1.1
					_sfx("push")
					push_cd = randf_range(3.0, 5.0)
					boost = 1.0
		else:
			push_t = 0.0
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
		if mount_t > 0.0:
			_play("skate_mount")
		elif push_t > 0.0:
			_play("skate_kick")
		elif mag > 0.25 and skate_speed < _smax() * mag * 0.7:
			_play("skate_push")
		elif mag <= 0.25 and skate_speed < 1.2:
			_play("skate_stand")
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
	_roll_update()
	for i in range(coin_nodes.size()):
		var c: Node3D = coin_nodes[i]
		if c.visible:
			c.rotation.y += 2.5 * d
			if state == "play" and player != null and c.global_position.distance_to(player.global_position + Vector3(0, 0.9, 0)) < 1.1:
				c.visible = false
				coin_respawn[i] = 45.0
				_sfx("coin")
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
		_story_process(d)
		_npcs_update(d)
		_act_update()
	mini.visible = state == "play"
	mini.position = Vector2(_vs().x - MM_SIZE - 20, 84)
	mini.queue_redraw()
	if player == null or model == null:
		return
	vis_h = lerp_angle(vis_h, heading, minf(1.0, 18.0 * d))
	var tgt_up := player.get_floor_normal() if (skating and player.is_on_floor()) else Vector3.UP
	vis_up = vis_up.lerp(tgt_up, minf(1.0, 12.0 * d)).normalized()
	var vf := Vector3(sin(vis_h), 0, cos(vis_h))
	var vz := (vf - vis_up * vf.dot(vis_up)).normalized()
	var vx := vis_up.cross(vz).normalized()
	visual.basis = Basis(vx, vis_up, vz)
	var lift := SKATE_LIFT if skating else 0.0
	var lk := 7.0 if mount_t > 0.0 else 15.0
	model.position.y = lerpf(model.position.y, MODEL_SCALE + lift, minf(1.0, lk * d))
	model.position.x = lerpf(model.position.x, 0.25 if skating else 0.0, minf(1.0, lk * d))
	model.position.z = lerpf(model.position.z, 0.0 if skating else 0.0, minf(1.0, 15.0 * d))
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
	var target: Vector3 = ip + Vector3(0, 1.7, 0)
	cam_pivot.global_position = cam_pivot.global_position.lerp(target, minf(1.0, 12.0 * d))
	hud.queue_redraw()
