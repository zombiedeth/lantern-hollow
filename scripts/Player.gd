# Player.gd — A small glowing spirit creature that follows touch/click.
extends CharacterBody2D

@export var move_speed: float = 280.0

var target: Vector2 = Vector2.ZERO
var is_moving: bool = false

# Visual nodes (created in code)
var _body: Sprite2D
var _glow: PointLight2D
var _trail_timer: float = 0.0

func _ready() -> void:
	add_to_group("player")
	target = position

	# Glow light that follows the player
	_glow = PointLight2D.new()
	_glow.texture = _make_circle_texture(128)
	_glow.color = Color(1.0, 0.9, 0.6)
	_glow.energy = 1.8
	_glow.height = 0
	add_child(_glow)

	# Body — a soft glowing orb with a face
	_body = Sprite2D.new()
	_body.texture = _make_spirit_texture()
	add_child(_body)

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
				var c := Color(1, 1, 1, alpha)
				img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

func _make_spirit_texture() -> ImageTexture:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := size / 2.0
	var body_radius := 18.0

	for y in range(size):
		for x in range(size):
			var dx := x - center
			var dy := y - center
			var dist := sqrt(dx * dx + dy * dy)

			if dist <= body_radius:
				# Body fill — warm cream
				var c := Color(1.0, 0.96, 0.85, 1.0)
				# Soft outer edge
				if dist > body_radius - 2.0:
					c.a = smoothstep(body_radius, body_radius - 4.0, dist)
				img.set_pixel(x, y, c)
			elif dist <= body_radius + 6:
				# Glow halo
				var t := 1.0 - (dist - body_radius) / 6.0
				var alpha := smoothstep(0.0, 1.0, t) * 0.5
				img.set_pixel(x, y, Color(1.0, 0.9, 0.5, alpha))

	# Eyes — two small dark dots
	_draw_dot(img, center - 5, center - 3, 2.5, Color(0.15, 0.1, 0.2))
	_draw_dot(img, center + 5, center - 3, 2.5, Color(0.15, 0.1, 0.2))
	# Cheeks — soft pink blush
	_draw_dot(img, center - 9, center + 4, 2.0, Color(1.0, 0.5, 0.5, 0.4))
	_draw_dot(img, center + 9, center + 4, 2.0, Color(1.0, 0.5, 0.5, 0.4))

	return ImageTexture.create_from_image(img)

func _draw_dot(img: Image, cx: float, cy: float, r: float, color: Color) -> void:
	for y in range(int(cx - r - 1), int(cx + r + 2)):
		for x in range(int(cy - r - 1), int(cy + r + 2)):
			var dx := x - cx
			var dy := y - cy
			if sqrt(dx * dx + dy * dy) <= r:
				if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
					var existing := img.get_pixel(x, y)
					if existing.a < color.a:
						img.set_pixel(x, y, color)

func _physics_process(delta: float) -> void:
	if is_moving:
		var dir := (target - position)
		var dist := dir.length()
		if dist > 5.0:
			velocity = dir.normalized() * move_speed
		else:
			velocity = Vector2.ZERO
			is_moving = false
	else:
		velocity = Vector2.ZERO

	# Gentle idle bob
	_body.position.y = sin(Time.get_ticks_msec() * 0.003) * 2.0

	move_and_slide()

	# Spawn trail particles occasionally
	_trail_timer += delta
	if is_moving and _trail_timer > 0.05:
		_trail_timer = 0.0
		_spawn_trail()

func _spawn_trail() -> void:
	var trail := GPUParticles2D.new()
	trail.position = position
	trail.emitting = true
	trail.one_shot = true
	trail.amount = 3
	trail.lifetime = 0.5
	trail.explosiveness = 1.0
	trail.process_material = _make_trail_material()
	get_parent().add_child(trail)

	# Clean up after particles finish
	get_tree().create_timer(1.5).timeout.connect(trail.queue_free)

func _make_trail_material() -> ParticleProcessMaterial:
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 0, 0)
	mat.spread = 30.0
	mat.gravity = Vector3(0, 0, 0)
	mat.initial_velocity_min = 5.0
	mat.initial_velocity_max = 15.0
	mat.scale_min = 0.3
	mat.scale_max = 0.6
	mat.color = Color(1.0, 0.9, 0.5, 0.6)

	var tex := _make_circle_texture(16)
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	return mat

func move_to(pos: Vector2) -> void:
	target = pos
	is_moving = true
