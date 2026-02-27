extends Node3D

enum GameState { READY, PLAYING, GAME_OVER }

const PIPE_SPAWN_INTERVAL: float = 1.7
const GAP_SIZE: float = 3.8
const GAP_MIN_Y: float = 3.5
const GAP_MAX_Y: float = 11.5
const PIPE_SPAWN_X: float = 28.0

var state: int = GameState.READY
var score: int = 0
var best_score: int = 0

var bird: CharacterBody3D = null
var pipe_container: Node3D = null
var spawn_timer: Timer = null
var sound: Node = null

var score_label: Label = null
var message_label: Label = null
var game_over_container: VBoxContainer = null

var _restart_cooldown: bool = false

# Parallax background tracking: [{node, speed, wrap_width}]
var _bg_elements: Array = []
const BG_BASE_SPEED: float = 4.5
const BG_LEFT_LIMIT: float = -20.0
const BG_WRAP_WIDTH: float = 50.0


func _ready() -> void:
	_setup_sound()
	_setup_environment()
	_setup_camera()
	_setup_lighting()
	_setup_ground()
	_setup_bird()
	_setup_pipes()
	_setup_countryside()
	_setup_ui()
	_show_ready_screen()


# ==============================================================
#  SCENE SETUP
# ==============================================================

func _setup_sound() -> void:
	sound = Node.new()
	sound.set_script(preload("res://sound_manager.gd"))
	sound.name = "SoundManager"
	add_child(sound)


func _setup_environment() -> void:
	# Warm Vietnamese countryside sky — golden hour feel
	var sky_mat: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.40, 0.65, 0.90)
	sky_mat.sky_horizon_color = Color(0.90, 0.78, 0.55)
	sky_mat.ground_bottom_color = Color(0.30, 0.45, 0.18)
	sky_mat.ground_horizon_color = Color(0.75, 0.70, 0.50)

	var sky: Sky = Sky.new()
	sky.sky_material = sky_mat

	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_color = Color(0.90, 0.85, 0.75)
	env.ambient_light_energy = 0.55

	var world_env: WorldEnvironment = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


func _setup_camera() -> void:
	# Landscape 16:9 – camera further back, centered on wider play area
	var cam: Camera3D = Camera3D.new()
	cam.position = Vector3(5, 7, 20)
	cam.fov = 45
	cam.current = true
	add_child(cam)


func _setup_lighting() -> void:
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -20, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.97, 0.93)
	sun.directional_shadow_max_distance = 80.0
	sun.shadow_normal_bias = 2.0
	sun.shadow_bias = 0.1
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	add_child(sun)


func _setup_ground() -> void:
	# Rice-paddy earth
	var ground: StaticBody3D = StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = 4
	ground.collision_mask = 0
	ground.position = Vector3(5, -0.5, 0)

	var g_mesh: MeshInstance3D = MeshInstance3D.new()
	var g_box: BoxMesh = BoxMesh.new()
	g_box.size = Vector3(60, 1, 14)
	var g_mat: StandardMaterial3D = StandardMaterial3D.new()
	g_mat.albedo_color = Color(0.55, 0.42, 0.25)
	g_mat.roughness = 0.95
	g_box.material = g_mat
	g_mesh.mesh = g_box
	ground.add_child(g_mesh)

	var g_col: CollisionShape3D = CollisionShape3D.new()
	var g_shape: BoxShape3D = BoxShape3D.new()
	g_shape.size = Vector3(60, 1, 14)
	g_col.shape = g_shape
	ground.add_child(g_col)
	add_child(ground)

	# Green rice paddy top layer
	var paddy: MeshInstance3D = MeshInstance3D.new()
	var paddy_box: BoxMesh = BoxMesh.new()
	paddy_box.size = Vector3(60, 0.12, 14)
	var paddy_mat: StandardMaterial3D = StandardMaterial3D.new()
	paddy_mat.albedo_color = Color(0.35, 0.60, 0.15)
	paddy_mat.roughness = 0.85
	paddy_box.material = paddy_mat
	paddy.mesh = paddy_box
	paddy.position = Vector3(5, 0.06, 0)
	add_child(paddy)

	# Dirt path strip (đường làng)
	var path: MeshInstance3D = MeshInstance3D.new()
	var path_box: BoxMesh = BoxMesh.new()
	path_box.size = Vector3(60, 0.13, 1.2)
	var path_mat: StandardMaterial3D = StandardMaterial3D.new()
	path_mat.albedo_color = Color(0.70, 0.58, 0.38)
	path_mat.roughness = 0.9
	path_box.material = path_mat
	path.mesh = path_box
	path.position = Vector3(5, 0.065, 2.0)
	add_child(path)

	# Invisible ceiling
	var ceiling: StaticBody3D = StaticBody3D.new()
	ceiling.name = "Ceiling"
	ceiling.collision_layer = 4
	ceiling.collision_mask = 0
	ceiling.position = Vector3(5, 15.5, 0)

	var c_col: CollisionShape3D = CollisionShape3D.new()
	var c_shape: BoxShape3D = BoxShape3D.new()
	c_shape.size = Vector3(60, 1, 14)
	c_col.shape = c_shape
	ceiling.add_child(c_col)
	add_child(ceiling)


func _setup_bird() -> void:
	bird = CharacterBody3D.new()
	bird.set_script(preload("res://bird.gd"))
	bird.position = Vector3(0, 7, 0)
	add_child(bird)
	bird.died.connect(_on_bird_died)


func _setup_pipes() -> void:
	pipe_container = Node3D.new()
	pipe_container.name = "Pipes"
	add_child(pipe_container)

	spawn_timer = Timer.new()
	spawn_timer.wait_time = PIPE_SPAWN_INTERVAL
	spawn_timer.one_shot = false
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(spawn_timer)


func _setup_countryside() -> void:
	_create_bamboo_groves()
	_create_village_houses()
	_create_clouds()


func _register_bg(node: Node3D, z_depth: float) -> void:
	# Deeper Z = slower parallax. Speed factor: 0.15 (far) to 0.6 (near)
	var factor: float = clampf(1.0 / (1.0 + absf(z_depth) * 0.25), 0.12, 0.65)
	_bg_elements.append({"node": node, "speed": BG_BASE_SPEED * factor})


func _create_bamboo_groves() -> void:
	var bamboo_green: StandardMaterial3D = StandardMaterial3D.new()
	bamboo_green.albedo_color = Color(0.28, 0.52, 0.18)
	bamboo_green.roughness = 0.7

	var bamboo_dark: StandardMaterial3D = StandardMaterial3D.new()
	bamboo_dark.albedo_color = Color(0.22, 0.42, 0.14)
	bamboo_dark.roughness = 0.7

	var leaf_mat: StandardMaterial3D = StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.30, 0.55, 0.15, 0.85)
	leaf_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	leaf_mat.roughness = 0.8

	var clusters: Array = [
		Vector3(-8, 0, -5), Vector3(-4, 0, -7), Vector3(2, 0, -6),
		Vector3(8, 0, -8), Vector3(14, 0, -5), Vector3(18, 0, -7),
		Vector3(22, 0, -6), Vector3(-2, 0, -9), Vector3(11, 0, -9),
		Vector3(25, 0, -5), Vector3(30, 0, -7), Vector3(35, 0, -6),
	]

	for cluster_pos: Vector3 in clusters:
		# Group each cluster into a single Node3D for parallax
		var group: Node3D = Node3D.new()
		group.position = Vector3(cluster_pos.x, 0, cluster_pos.z)
		add_child(group)
		_register_bg(group, cluster_pos.z)

		var stalks: int = randi_range(3, 6)
		for j: int in range(stalks):
			var stalk: MeshInstance3D = MeshInstance3D.new()
			var cyl: CylinderMesh = CylinderMesh.new()
			var h: float = randf_range(6.0, 12.0)
			cyl.top_radius = randf_range(0.06, 0.10)
			cyl.bottom_radius = randf_range(0.10, 0.16)
			cyl.height = h
			cyl.material = bamboo_green if j % 2 == 0 else bamboo_dark
			stalk.mesh = cyl
			stalk.position = Vector3(randf_range(-0.8, 0.8), h / 2.0, randf_range(-0.5, 0.5))
			stalk.rotation_degrees.z = randf_range(-3.0, 3.0)
			group.add_child(stalk)

			var leaf: MeshInstance3D = MeshInstance3D.new()
			var leaf_mesh: SphereMesh = SphereMesh.new()
			leaf_mesh.radius = randf_range(0.5, 1.0)
			leaf_mesh.height = randf_range(0.6, 1.0)
			leaf_mesh.material = leaf_mat
			leaf.mesh = leaf_mesh
			leaf.position = Vector3(randf_range(-0.5, 0.5), h + randf_range(-0.3, 0.5), randf_range(-0.3, 0.3))
			group.add_child(leaf)


func _create_village_houses() -> void:
	var wall_mat: StandardMaterial3D = StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.85, 0.75, 0.55)
	wall_mat.roughness = 0.9

	var roof_mat: StandardMaterial3D = StandardMaterial3D.new()
	roof_mat.albedo_color = Color(0.50, 0.28, 0.12)
	roof_mat.roughness = 0.8

	var red_wall: StandardMaterial3D = StandardMaterial3D.new()
	red_wall.albedo_color = Color(0.72, 0.45, 0.25)
	red_wall.roughness = 0.85

	var house_positions: Array = [
		Vector3(-5, 0, -10), Vector3(5, 0, -12),
		Vector3(15, 0, -11), Vector3(23, 0, -10),
		Vector3(33, 0, -11), Vector3(40, 0, -12),
	]

	for pos: Vector3 in house_positions:
		var group: Node3D = Node3D.new()
		group.position = Vector3(pos.x, 0, pos.z)
		add_child(group)
		_register_bg(group, pos.z)

		var w: float = randf_range(1.5, 2.5)
		var h: float = randf_range(1.5, 2.2)
		var d: float = randf_range(1.8, 2.8)

		# Walls
		var walls: MeshInstance3D = MeshInstance3D.new()
		var wall_mesh: BoxMesh = BoxMesh.new()
		wall_mesh.size = Vector3(w, h, d)
		wall_mesh.material = wall_mat if randi() % 2 == 0 else red_wall
		walls.mesh = wall_mesh
		walls.position.y = h / 2.0
		group.add_child(walls)

		# Roof
		var roof: MeshInstance3D = MeshInstance3D.new()
		var roof_mesh: PrismMesh = PrismMesh.new()
		roof_mesh.size = Vector3(w + 0.4, 0.8, d + 0.4)
		roof_mesh.material = roof_mat
		roof.mesh = roof_mesh
		roof.position.y = h + 0.4
		group.add_child(roof)


func _create_clouds() -> void:
	var cloud_mat: StandardMaterial3D = StandardMaterial3D.new()
	cloud_mat.albedo_color = Color(1, 1, 1, 0.45)
	cloud_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cloud_mat.roughness = 1.0

	for i: int in range(8):
		var cloud: MeshInstance3D = MeshInstance3D.new()
		var s: SphereMesh = SphereMesh.new()
		var r: float = randf_range(1.0, 2.8)
		s.radius = r
		s.height = r * 0.8
		s.material = cloud_mat
		cloud.mesh = s
		var z: float = randf_range(-16.0, -8.0)
		cloud.position = Vector3(
			randf_range(-8.0, 35.0),
			randf_range(11.0, 14.0),
			z
		)
		add_child(cloud)
		_register_bg(cloud, z)


# ==============================================================
#  PARALLAX SCROLLING
# ==============================================================

func _process(delta: float) -> void:
	if state != GameState.PLAYING:
		return
	for entry: Dictionary in _bg_elements:
		var node: Node3D = entry["node"]
		if not is_instance_valid(node):
			continue
		node.position.x -= entry["speed"] * delta
		if node.position.x < BG_LEFT_LIMIT:
			node.position.x += BG_WRAP_WIDTH


# ==============================================================
#  UI  (1280 × 720 landscape, Vietnamese)
# ==============================================================

func _setup_ui() -> void:
	var canvas: CanvasLayer = CanvasLayer.new()
	canvas.name = "UI"
	add_child(canvas)

	# --- Score (top center, anchored) ---
	score_label = Label.new()
	score_label.text = "0"
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	score_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	score_label.offset_top = 20
	score_label.offset_bottom = 100
	score_label.add_theme_font_size_override("font_size", 72)
	score_label.add_theme_color_override("font_color", Color.WHITE)
	score_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	score_label.add_theme_constant_override("shadow_offset_x", 3)
	score_label.add_theme_constant_override("shadow_offset_y", 3)
	score_label.visible = false
	canvas.add_child(score_label)

	# --- Start message (full-screen centered) ---
	message_label = Label.new()
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	message_label.add_theme_font_size_override("font_size", 42)
	message_label.add_theme_color_override("font_color", Color.WHITE)
	message_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	message_label.add_theme_constant_override("shadow_offset_x", 2)
	message_label.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(message_label)

	# --- Game-over panel (full-screen anchored, centered) ---
	game_over_container = VBoxContainer.new()
	game_over_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	game_over_container.alignment = BoxContainer.ALIGNMENT_CENTER
	game_over_container.visible = false
	canvas.add_child(game_over_container)

	var go_label: Label = Label.new()
	go_label.text = "KẾT THÚC"
	go_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	go_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go_label.add_theme_font_size_override("font_size", 52)
	go_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	go_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	go_label.add_theme_constant_override("shadow_offset_x", 2)
	go_label.add_theme_constant_override("shadow_offset_y", 2)
	game_over_container.add_child(go_label)

	var spacer1: Control = Control.new()
	spacer1.custom_minimum_size = Vector2(0, 15)
	game_over_container.add_child(spacer1)

	var score_disp: Label = Label.new()
	score_disp.name = "ScoreDisplay"
	score_disp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_disp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	score_disp.add_theme_font_size_override("font_size", 36)
	score_disp.add_theme_color_override("font_color", Color.WHITE)
	game_over_container.add_child(score_disp)

	var best_disp: Label = Label.new()
	best_disp.name = "BestDisplay"
	best_disp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	best_disp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	best_disp.add_theme_font_size_override("font_size", 30)
	best_disp.add_theme_color_override("font_color", Color(1, 0.84, 0))
	game_over_container.add_child(best_disp)

	var spacer2: Control = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 30)
	game_over_container.add_child(spacer2)

	var restart_lbl: Label = Label.new()
	restart_lbl.text = "Nhấn chuột hoặc Space\nđể chơi lại"
	restart_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	restart_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	restart_lbl.add_theme_font_size_override("font_size", 28)
	restart_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 0.85))
	game_over_container.add_child(restart_lbl)


# ==============================================================
#  INPUT
# ==============================================================

func _unhandled_input(event: InputEvent) -> void:
	if not _is_action_event(event):
		return

	match state:
		GameState.READY:
			_start_game()
			bird.flap()
			sound.play_flap()
		GameState.PLAYING:
			bird.flap()
			sound.play_flap()
		GameState.GAME_OVER:
			if not _restart_cooldown:
				_restart_game()


func _is_action_event(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		return event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if event is InputEventKey:
		return event.pressed and not event.echo and event.keycode == KEY_SPACE
	if event is InputEventScreenTouch:
		return event.pressed
	return false


# ==============================================================
#  GAME FLOW
# ==============================================================

func _show_ready_screen() -> void:
	message_label.text = "Nhấn chuột hoặc phím Space để bắt đầu"
	message_label.visible = true
	score_label.visible = false
	game_over_container.visible = false


func _start_game() -> void:
	state = GameState.PLAYING
	score = 0
	score_label.text = "0"
	score_label.visible = true
	message_label.visible = false
	bird.start()
	spawn_timer.start()
	sound.play_bgm()


func _on_spawn_timer_timeout() -> void:
	_spawn_pipe()


func _spawn_pipe() -> void:
	var pipe: Node3D = Node3D.new()
	pipe.set_script(preload("res://pipe.gd"))
	pipe.position.x = PIPE_SPAWN_X
	pipe_container.add_child(pipe)

	var gap_center: float = randf_range(GAP_MIN_Y, GAP_MAX_Y)
	pipe.setup(gap_center, GAP_SIZE)
	pipe.is_moving = true
	pipe.score_triggered.connect(_on_pipe_scored)


func _on_pipe_scored() -> void:
	if state == GameState.PLAYING:
		score += 1
		score_label.text = str(score)
		sound.play_score()


func _on_bird_died() -> void:
	state = GameState.GAME_OVER
	spawn_timer.stop()
	_restart_cooldown = true
	sound.stop_bgm()
	sound.play_hit()

	for pipe: Node3D in pipe_container.get_children():
		pipe.set("is_moving", false)

	if score > best_score:
		best_score = score

	await get_tree().create_timer(0.4).timeout
	sound.play_die()

	await get_tree().create_timer(0.6).timeout

	score_label.visible = false
	game_over_container.visible = true
	game_over_container.get_node("ScoreDisplay").text = "Điểm: " + str(score)
	game_over_container.get_node("BestDisplay").text = "Kỷ lục: " + str(best_score)

	await get_tree().create_timer(0.3).timeout
	_restart_cooldown = false


func _restart_game() -> void:
	state = GameState.READY

	for pipe: Node3D in pipe_container.get_children():
		pipe.queue_free()

	bird.reset()
	_show_ready_screen()
