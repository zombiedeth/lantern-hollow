# Plant.gd — A plantable flower that grows and blooms with light.
extends Node2D

enum State { SEED, SPROUT, BLOOM }

@export var plant_id: String = "sparkle"

var state: State = State.SEED
var growth_time: float = 0.0
var bloom_time: float = 8.0
var value: int = 5
var petal_color: Color = Color(1.0, 0.82, 0.4)
var glow_color: Color = Color(1.0, 0.85, 0.3)

var _petals: Sprite2D
var _light: PointLight2D
var _stem: Sprite2D
var _particles: GPUParticles2D

func _ready() -> void:
	# Load plant data
	var data: Dictionary = GameState.PLANTS.get(plant_id, GameState.PLANTS["sparkle"])
	petal_color = data.get("petal_color", petal_color)
	glow_color = data.get("glow_color", glow_color)
	bloom_time = data.get("bloom_time", bloom_time)
	value = data.get("value", value)

	_apply_state_visual()

func _apply_state_visual() -> void:
	# Clear children
	for child in get_children():
		child.queue_free()
	await get_tree().process_frame  # Let frees process

	# Stem
	_stem = Sprite2D.new()
	_stem.texture = _make_stem_texture(state)
	add_child(_stem)

	# Light (off until bloom)
	_light = PointLight2D.new()
	_light.texture = _make_circle_texture(96)
	_light.color = glow_color
	_light.energy = 0.0 if state != State.BLOOM else 1.6
	_light.height = 0
	add_child(_light)

	# Petals (only on bloom)
	if state == State.BLOOM:
		_petals = Sprite2D.new()
		_petals.texture = _make_flower_texture()
		add_child(_petals)

		# Sparkle particles when bloomed
		_particles = GPUParticles2D.new()
		_particles.amount = 8
		_particles.lifetime = 2.0
		_particles.explosiveness = 0.0
		_particles.process_material = _make_sparkle_material()
		var quad := QuadMesh.new()
		quad.size = Vector2(4, 4)
		_particles.texture = _make_circle_texture(8)
		add_child(_particles)

func _process(delta: float) -> void:
	if state == State.BLOOM:
		# Gentle pulse
		var pulse := 1.4 + sin(Time.get_ticks_msec() * 0.002 + position.x * 0.01) * 0.3
		if _light:
			_light.energy = pulse
		if _petals:
			_petals.rotation += delta * 0.1
	else:
		growth_time += delta
		if state == State.SEED and growth_time > bloom_time * 0.4:
			state = State.SPROUT
			_apply_state_visual()
		elif state == State.SPROUT and growth_time > bloom_time:
			state = State.BLOOM
			_apply_state_visual()
			_on_bloom()

func _on_bloom() -> void:
	# Spawn a burst of sparkle particles
	var burst := GPUParticles2D.new()
	burst.amount = 20
	burst.lifetime = 1.0
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.process_material = _make_burst_material()
	burst.texture = _make_circle_texture(12)
	add_child(burst)

	# Auto-clean
	get_tree().create_timer(2.0).timeout.connect(burst.queue_free)

# --- Texture generation ---

func _make_circle_texture(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := size / 2.0
	var radius := center
	for y in range(size):
		for x in range(size):
			var dx := x - center
			var dy := y - center
			var dist := sqrt(dx * dx + dy * dy)
			if dist <= radius:
				var t := 1.0 - (dist / radius)
				var alpha := smoothstep(0.0, 1.0, t)
				img.set_pixel(x, y, Color(1, 1, 1, alpha))
	return ImageTexture.create_from_image(img)

func _make_stem_texture(s: State) -> ImageTexture:
	var size := 48
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)

	var cx := size / 2.0
	var base_y := size - 4.0

	if s == State.SEED:
		# Small mound
		for y in range(size):
			for x in range(size):
				var dx := x - cx
				var dy := y - base_y
				var dist := sqrt(dx * dx * 0.5 + dy * dy)
				if dist <= 6.0:
					var c := Color(0.35, 0.25, 0.15, 1.0)
					img.set_pixel(x, y, c)

	elif s == State.SPROUT:
		# Stem + two tiny leaves
		for y in range(size):
			for x in range(size):
				var dx := x - cx
				# Stem
				if abs(dx) <= 1.5 and y > base_y - 16 and y < base_y:
					img.set_pixel(x, y, Color(0.25, 0.4, 0.2))
				# Leaves
				var stem_y := y - base_y + 10
				if stem_y > 0 and stem_y < 6:
					if dx > -10 and dx < -2:
						img.set_pixel(x, y, Color(0.3, 0.5, 0.25))
					if dx > 2 and dx < 10:
						img.set_pixel(x, y, Color(0.3, 0.0, 0.25))

	elif s == State.BLOOM:
		# Full stem
		for y in range(size):
			for x in range(size):
				var dx := x - cx
				if abs(dx) <= 1.5 and y > base_y - 20 and y < base_y:
					img.set_pixel(x, y, Color(0.25, 0.4, 0.2))

	return ImageTexture.create_from_image(img)

func _make_flower_texture() -> ImageTexture:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := size / 2.0

	# 6 petals around center
	var petal_count := 6
	for i in range(petal_count):
		var angle := (float(i) / petal_count) * TAU
		var px := center + cos(angle) * 12
		var py := center + sin(angle) * 12
		for y in range(size):
			for x in range(size):
				var dx := x - px
				var dy := y - py
				var dist := sqrt(dx * dx + dy * dy)
				if dist <= 9.0:
					var t := 1.0 - (dist / 9.0)
					var c := petal_color
					c.a = smoothstep(0.0, 0.5, t)
					var existing := img.get_pixel(x, y)
					if existing.a < c.a:
						img.set_pixel(x, y, c)

	# Center
	for y in range(size):
		for x in range(size):
			var dx := x - center
			var dy := y - center
			var dist := sqrt(dx * dx + dy * dy)
			if dist <= 6.0:
				img.set_pixel(x, y, Color(1.0, 0.85, 0.3))

	return ImageTexture.create_from_image(img)

func _make_sparkle_material() -> ParticleProcessMaterial:
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 20.0
	mat.gravity = Vector3(0, 5, 0)
	mat.initial_velocity_min = 3.0
	mat.initial_velocity_max = 8.0
	mat.scale_min = 0.2
	mat.scale_max = 0.5
	mat.color = glow_color

	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 10.0
	return mat

func _make_burst_material() -> ParticleProcessMaterial:
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 0, 0)
	mat.spread = 180.0
	mat.gravity = Vector3(0, 0, 0)
	mat.initial_velocity_min = 30.0
	mat.initial_velocity_max = 60.0
	mat.scale_min = 0.3
	mat_scale_max_set(mat, 0.8)
	mat.color = glow_color
	return mat

func _scale_max_set(mat: ParticleProcessMaterial, v: float) -> void:
	mat.scale_max = v

# Wrapper to avoid typo above
func mat_scale_max_set(mat: ParticleProcessMaterial, v: float) -> void:
	mat.scale_max = v

func is_bloomed() -> bool:
	return state == State.BLOOM

func harvest() -> void:
	# Play harvest animation then remove
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(1.5, 1.5), 0.2)
	tween.tween_property(self, "scale", Vector2.ZERO, 0.3)
	tween.tween_callback(queue_free)
