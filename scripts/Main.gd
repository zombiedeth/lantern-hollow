# Main.gd — Lantern Hollow: clearer progression + tutorial + juice pass.
# Goals: make every new layer explain itself, make ascensions unlock real toys, and make fairies feel alive.
extends Node2D

const W := 540.0
const H := 960.0
const COLS := 5
const ROWS := 6
const BASE_PLOTS := COLS * ROWS
const EXTRA_PLOTS := 10
const PLOT_SPACING := 82.0
const PLOT_START := Vector2(106, 235)
const PLAYER_SPEED := 520.0

const BG := preload("res://assets/generated/lantern_hollow_bg.png")
const TEX_SPIRIT := preload("res://assets/generated/sprites/spirit.png")
const TEX_SEED := preload("res://assets/generated/sprites/seed.png")
const TEX_SPROUT := preload("res://assets/generated/sprites/sprout.png")
const TEX_FLOWER_SPARK := preload("res://assets/generated/sprites/flower_spark.png")
const TEX_FLOWER_MOON := preload("res://assets/generated/sprites/flower_moon.png")
const TEX_FLOWER_EMBER := preload("res://assets/generated/sprites/flower_ember.png")
const TEX_LANTERN := preload("res://assets/generated/sprites/lantern.png")
const TEX_COIN := preload("res://assets/generated/sprites/coin.png")

const MUSIC_GLOWING_GARDEN := preload("res://assets/audio/music_07_glowing_garden.mp3")
# Music rule: ONE background song only. Glowing Garden is the base music.
# Procedural music stems are intentionally not loaded; only SFX layer on top.
const SFX_PLANT := preload("res://assets/audio/sfx_plant.wav")
const SFX_BLOOM := preload("res://assets/audio/sfx_bloom.wav")
const SFX_HARVEST := preload("res://assets/audio/sfx_harvest.wav")
const SFX_UPGRADE := preload("res://assets/audio/sfx_upgrade.wav")
const SFX_FAIRY := preload("res://assets/audio/sfx_fairy.wav")
const SFX_ASCEND := preload("res://assets/audio/sfx_ascend.wav")

class PlantData:
	var id: String
	var name: String
	var cost: int
	var payout: int
	var grow_time: float
	var color: Color
	var tex: Texture2D
	var hint: String
	func _init(p_id: String, p_name: String, p_cost: int, p_payout: int, p_grow: float, p_color: Color, p_tex: Texture2D, p_hint: String) -> void:
		id = p_id
		name = p_name
		cost = p_cost
		payout = p_payout
		grow_time = p_grow
		color = p_color
		tex = p_tex
		hint = p_hint

var catalog: Array[PlantData]
var selected_index := 0
var coins := 12
var message := "Welcome! Tap a dirt bed to plant Sparkbuds. Harvest blooms for glow."
var message_timer := 0.0

# Progression state.
var lantern_level := 0
var moonwell_unlocked := false
var constellarium_unlocked := false
var ascensions := 0
var stardust := 0
var sprite_helpers := 0
var auto_harvest_timer := 0.0
var auto_plant_timer := 0.0

# Audio.
var music_players: Dictionary = {}
var sfx_players: Dictionary = {}
var audio_ready := false
var music_started := false

# One-time guidance markers.
var seen_intro := false
var seen_lantern_hint := false
var seen_moonwell_hint := false
var seen_constellarium_hint := false
var seen_ascend_hint := false
var seen_auto_plant_hint := false
var seen_orchard_hint := false

# Effects.
var tap_rings: Array[Dictionary] = []
var sparkles: Array[Dictionary] = []
var beams: Array[Dictionary] = []
var pulse_cards: Array[Dictionary] = []
var active_prompt: Dictionary = {}
var ascension_fx := 0.0

# key = plot index, value = {kind:int, planted_at:float}
var plants: Dictionary = {}
var player_pos := Vector2(270, 760)
var player_target := Vector2(270, 760)

func _ready() -> void:
	catalog = [
		PlantData.new("spark", "Sparkbud", 2, 5, 5.0, Color(1.0, 0.80, 0.20), TEX_FLOWER_SPARK, "Cheap starter crop. Use it to get rolling."),
		PlantData.new("moon", "Moonblossom", 6, 13, 9.0, Color(0.45, 0.75, 1.0), TEX_FLOWER_MOON, "Better profit. First real upgrade crop."),
		PlantData.new("ember", "Emberlily", 12, 28, 14.0, Color(1.0, 0.35, 0.25), TEX_FLOWER_EMBER, "Funds your first infrastructure."),
		PlantData.new("star", "Starvine", 34, 96, 22.0, Color(0.95, 0.55, 1.0), TEX_FLOWER_MOON, "Moonwell crop. Big jump in glow."),
		PlantData.new("nova", "Nova Lotus", 140, 520, 34.0, Color(0.45, 1.0, 0.95), TEX_FLOWER_SPARK, "Constellarium crop. Late-game engine."),
		PlantData.new("sun", "Sunseed", 420, 1850, 46.0, Color(1.0, 0.58, 0.16), TEX_FLOWER_EMBER, "Ascended crop. Turns dust into absurd glow."),
	]
	print("LANTERN_HOLLOW_READY audio_build_v15_native_html_music")
	# Do not force the viewport to 540x960 here. Web/mobile shells provide
	# the real canvas size; _draw() scales the 540x960 stage to fill it.
	_setup_audio()
	_show_big_prompt("Lantern Hollow", "Plant seeds. Harvest blooms. Buy upgrades.\nEmberlilies lead to Moonwell, Moonwell leads to Starvine,\nand Ascension turns huge glow into permanent Stardust.", "Tap beds to begin.")
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	var to_target := player_target - player_pos
	if to_target.length() > 3.0:
		player_pos += to_target.normalized() * min(PLAYER_SPEED * delta, to_target.length())

	_update_effects(delta)
	_update_auto_systems(delta)
	_update_guidance()
	_update_adaptive_music(delta)
	queue_redraw()

func _stage_scale() -> Vector2:
	var vp := get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return Vector2.ONE
	# Fill the actual preview/browser/mobile canvas exactly. This prevents the
	# exported game from sitting tiny in a corner when the HTML canvas is larger
	# than the original 540x960 design stage.
	return Vector2(vp.x / W, vp.y / H)

func _screen_to_stage(pos: Vector2) -> Vector2:
	var s := _stage_scale()
	return Vector2(pos.x / maxf(0.001, s.x), pos.y / maxf(0.001, s.y))


func _setup_audio() -> void:
	# ONE music track only: Glowing Garden as the lofi base bed.
	# Progression sounds below are SFX only, not extra music stems.
	var stream: AudioStream = MUSIC_GLOWING_GARDEN
	# Force a valid play length on loop_end (bug in WAV import sets it to 0)
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
		wav.loop_end = wav.data.size() / 4  # bytes / (2 bytes/sample / 2 channels) = samples
	var base_player := AudioStreamPlayer.new()
	base_player.name = "Music_Base_Lofi"
	base_player.stream = stream
	base_player.volume_db = -15.0
	base_player.finished.connect(func():
		if music_started:
			base_player.play()
	)  # loop forever after first user tap
	add_child(base_player)
	# Do NOT play music in _ready(): iPhone Safari blocks autoplay.
	# _unlock_audio_from_gesture() starts this on the first touch/click.
	music_players["base"] = base_player
	var sfx := {"plant": SFX_PLANT, "bloom": SFX_BLOOM, "harvest": SFX_HARVEST, "upgrade": SFX_UPGRADE, "fairy": SFX_FAIRY, "ascend": SFX_ASCEND}
	for key in sfx.keys():
		var player := AudioStreamPlayer.new()
		player.name = "SFX_%s" % key
		player.stream = sfx[key]
		player.volume_db = -2.0
		add_child(player)
		sfx_players[key] = player
	audio_ready = true

func _unlock_audio_from_gesture() -> void:
	if not audio_ready or music_started or not music_players.has("base"):
		return
	music_started = true
	if OS.has_feature("web"):
		# Web/iPhone Safari: the exported HTML shell starts the lofi track with
		# a native <audio> element on the same user gesture. Do not also start
		# Godot's WebAudio music, because Safari showed it as playing but silent.
		print("LANTERN_HOLLOW_AUDIO_DELEGATED native_html_music")
		return
	var player: AudioStreamPlayer = music_players["base"]
	player.play()
	# iPhone Safari is picky: play one short SFX inside the same tap too.
	# This makes the audio unlock obvious and primes the WebAudio path.
	if sfx_players.has("plant"):
		var chirp: AudioStreamPlayer = sfx_players["plant"]
		chirp.stop()
		chirp.volume_db = -8.0
		chirp.play()
	print("LANTERN_HOLLOW_AUDIO_STARTED user_gesture_mp3")

func _play_sfx(key: String) -> void:
	if not audio_ready or not sfx_players.has(key):
		return
	# If the first audible thing is a button/SFX action, also unlock music.
	_unlock_audio_from_gesture()
	var player: AudioStreamPlayer = sfx_players[key]
	player.stop()
	player.play()

func _update_adaptive_music(delta: float) -> void:
	# No adaptive music layers anymore. Keep one lofi base song steady.
	# Web/iPhone uses native HTML audio from docs/index.html instead of Godot WebAudio.
	if OS.has_feature("web"):
		return
	# On native builds this must remain silent until the first user gesture.
	if not audio_ready or not music_started or not music_players.has("base"):
		return
	var player: AudioStreamPlayer = music_players["base"]
	if not player.playing:
		player.play()
	player.volume_db = lerpf(player.volume_db, -15.0, minf(1.0, delta * 1.8))

func _update_effects(delta: float) -> void:
	for r in tap_rings:
		r.age += delta
	tap_rings = tap_rings.filter(func(r): return r.age < 0.55)
	for s in sparkles:
		s.age += delta
		s.pos += s.vel * delta
	sparkles = sparkles.filter(func(s): return s.age < s.life)
	for b in beams:
		b.age += delta
	beams = beams.filter(func(b): return b.age < 0.45)
	for p in pulse_cards:
		p.age += delta
	pulse_cards = pulse_cards.filter(func(p): return p.age < 0.65)
	if not active_prompt.is_empty():
		active_prompt.age = float(active_prompt.get("age", 0.0)) + delta
	if message_timer > 0.0:
		message_timer -= delta
	if ascension_fx > 0.0:
		ascension_fx = maxf(0.0, ascension_fx - delta)

func _update_auto_systems(delta: float) -> void:
	if sprite_helpers <= 0:
		return
	auto_harvest_timer += delta
	# Sprite helpers are useful, but no longer instant-delete at 9 helpers.
	var harvest_interval: float = maxf(1.85, 5.5 / sqrt(float(sprite_helpers) + 0.5))
	if auto_harvest_timer >= harvest_interval:
		auto_harvest_timer = 0.0
		_auto_harvest_one()
	if _auto_plant_unlocked():
		auto_plant_timer += delta
		var plant_interval: float = maxf(1.1, 3.8 / sqrt(float(sprite_helpers) + 0.5))
		if auto_plant_timer >= plant_interval:
			auto_plant_timer = 0.0
			_auto_plant_one()

func _update_guidance() -> void:
	if not seen_lantern_hint and coins >= _lantern_cost():
		seen_lantern_hint = true
		_show_big_prompt("New upgrade: Lantern", "Lanterns speed up every crop.\nBuy these when waiting starts to feel slow.", "Tap the Lantern card above the seed bar.")
	if not seen_moonwell_hint and coins >= _moonwell_cost() and not moonwell_unlocked:
		seen_moonwell_hint = true
		_show_big_prompt("Next milestone: Moonwell", "Moonwell unlocks Starvine, the first big crop above Emberlily.\nThis is your first real progression gate.", "Save 120 glow, then tap Moonwell.")
	if moonwell_unlocked and not seen_constellarium_hint and coins >= _constellarium_cost() and not constellarium_unlocked:
		seen_constellarium_hint = true
		_show_big_prompt("Stars are waking", "The Constellarium unlocks Nova Lotus,\na crop made for late-game fairy gardens.", "Tap the Stars card when you have 1200 glow.")
	if constellarium_unlocked and not seen_ascend_hint and coins >= 3000:
		seen_ascend_hint = true
		_show_big_prompt("Ascension is near", "Ascension resets your garden, but gives Stardust.\nStardust permanently boosts payouts and growth.", "At 6500 glow, tap Ascend.")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_unlock_audio_from_gesture()
		_handle_tap(event.position)
	elif event is InputEventScreenTouch and event.pressed:
		_unlock_audio_from_gesture()
		_handle_tap(event.position)

func _handle_tap(screen_pos: Vector2) -> void:
	if not active_prompt.is_empty():
		active_prompt.clear()
		return

	var pos := _screen_to_stage(screen_pos)
	player_target = pos
	tap_rings.append({"pos": pos, "age": 0.0})

	for i in range(4):
		if _upgrade_rect(i).has_point(pos):
			_buy_upgrade(i)
			return

	if pos.y >= 832.0:
		var visible_count := _visible_catalog_size()
		var button_w := W / float(visible_count)
		var idx := clampi(int(pos.x / button_w), 0, visible_count - 1)
		selected_index = idx
		_flash("Selected %s — %s" % [catalog[idx].name, catalog[idx].hint])
		_add_pulse(_seed_rect(idx, visible_count), catalog[idx].color)
		return

	var plot_idx := _nearest_plot(pos)
	if plot_idx == -1:
		return

	if plants.has(plot_idx):
		var plant: Dictionary = plants[plot_idx]
		if _plant_stage(plant) >= 2:
			_harvest_plot(plot_idx, false)
		else:
			_flash("Still growing. Lanterns and Stardust make crops faster.")
		return

	_plant_plot(plot_idx, selected_index, false)

func _plant_plot(plot_idx: int, kind: int, automatic: bool) -> bool:
	if plot_idx < 0 or plot_idx >= _plot_count():
		return false
	if plants.has(plot_idx):
		return false
	if kind >= _visible_catalog_size():
		return false
	var selected := catalog[kind]
	if coins < selected.cost:
		if not automatic:
			_flash("Need %d glow for %s" % [selected.cost, selected.name])
		return false
	coins -= selected.cost
	plants[plot_idx] = {"kind": kind, "planted_at": Time.get_ticks_msec() / 1000.0}
	_spawn_sparkles(_plot_pos(plot_idx), selected.color, 12)
	_play_sfx("fairy" if automatic else "plant")
	if automatic:
		_flash("Fairies planted %s" % selected.name)
	else:
		_flash("Planted %s" % selected.name)
	return true

func _buy_upgrade(idx: int) -> void:
	if idx == 0:
		var cost := _lantern_cost()
		if coins < cost:
			_flash("Need %d glow for Lantern. Lanterns speed up all crops." % cost)
			return
		coins -= cost
		lantern_level += 1
		_add_pulse(_upgrade_rect(idx), Color(1.0, 0.78, 0.28))
		_spawn_sparkles(_upgrade_rect(idx).get_center(), Color(1.0, 0.78, 0.28), 28)
		_play_sfx("upgrade")
		_show_big_prompt("Lantern upgraded", "All crops grow faster.\nThis reduces waiting and makes expensive crops less painful.", "Lantern level %d" % lantern_level)
	elif idx == 1:
		if not moonwell_unlocked:
			var cost := _moonwell_cost()
			if coins < cost:
				_flash("Need %d glow. Moonwell unlocks Starvine." % cost)
				return
			coins -= cost
			moonwell_unlocked = true
			selected_index = 3
			_add_pulse(_upgrade_rect(idx), Color(0.72, 0.70, 1.0))
			_spawn_sparkles(_upgrade_rect(idx).get_center(), Color(0.72, 0.70, 1.0), 40)
			_play_sfx("upgrade")
			_show_big_prompt("Moonwell built", "Starvine is unlocked.\nStarvine is the crop that moves you beyond Emberlily farming.", "Plant Starvine from the seed bar.")
			return
		if not constellarium_unlocked:
			var cost := _constellarium_cost()
			if coins < cost:
				_flash("Need %d glow. Constellarium unlocks Nova Lotus." % cost)
				return
			coins -= cost
			constellarium_unlocked = true
			selected_index = 4
			_add_pulse(_upgrade_rect(idx), Color(0.55, 1.0, 0.95))
			_spawn_sparkles(Vector2(270, 410), Color(0.55, 1.0, 0.95), 70)
			_play_sfx("upgrade")
			_show_big_prompt("Constellarium lit", "Nova Lotus is unlocked.\nThis is your bridge from normal glow economy into Ascension.", "Grow Nova Lotus, then save for Ascension.")
			return
		_flash("Constellarium is active. Save glow for Ascension.")
	elif idx == 2:
		var cost := _sprite_cost()
		if coins < cost:
			_flash("Need %d glow. Sprites become visible fairies and automate harvests." % cost)
			return
		coins -= cost
		sprite_helpers += 1
		_add_pulse(_upgrade_rect(idx), Color(0.62, 1.0, 0.78))
		_spawn_sparkles(_upgrade_rect(idx).get_center(), Color(0.62, 1.0, 0.78), 34)
		_play_sfx("fairy")
		if _auto_plant_unlocked() and not seen_auto_plant_hint:
			seen_auto_plant_hint = true
			_show_big_prompt("Fairies learned to plant", "Ascend 2 unlocks auto-planting.\nYour fairies now fill empty beds with the selected crop when you can afford it.", "Choose a seed, then let them help.")
		else:
			_flash("Fairy Helper %d: auto-harvests blooms" % sprite_helpers)
	elif idx == 3:
		var cost := _ascend_cost()
		if coins < cost:
			_flash("Need %d glow. Ascension gives permanent Stardust." % cost)
			return
		var earned := 1 + int(floor(float(coins - cost) / 3000.0))
		stardust += earned
		ascensions += 1
		coins = 20 + stardust * 8
		plants.clear()
		lantern_level = 0
		sprite_helpers = 0
		auto_harvest_timer = 0.0
		auto_plant_timer = 0.0
		moonwell_unlocked = true
		constellarium_unlocked = true
		selected_index = 5
		ascension_fx = 2.8
		_spawn_sparkles(Vector2(270, 390), Color(1.0, 0.55, 0.95), 120)
		_play_sfx("ascend")
		if ascensions == 1:
			_show_big_prompt("Ascension I", "+%d Stardust earned.\nSunseed is unlocked. Stardust boosts all payouts and growth forever." % earned, "Rebuild faster with Sunseed.")
		elif ascensions == 2:
			seen_auto_plant_hint = true
			_show_big_prompt("Ascension II", "+%d Stardust earned.\nFairies can now auto-plant the selected seed into empty beds." % earned, "Buy fairies, pick a seed, and watch them garden.")
		elif ascensions == 3:
			seen_orchard_hint = true
			_show_big_prompt("Ascension III", "+%d Stardust earned.\nNebula Orchard unlocked: ten extra side beds appear." % earned, "More beds means bigger fairy gardens.")
		else:
			_show_big_prompt("Ascension %d" % ascensions, "+%d Stardust earned.\nEach Ascension makes every future loop richer and faster." % earned, "Keep stacking dust or chase a bigger garden.")

func _auto_harvest_one() -> void:
	for key in plants.keys():
		var plant: Dictionary = plants[key]
		if _plant_stage(plant) >= 2:
			_harvest_plot(int(key), true)
			return

func _auto_plant_one() -> void:
	if selected_index >= _visible_catalog_size():
		selected_index = _visible_catalog_size() - 1
	for i in range(_plot_count()):
		if not plants.has(i):
			if _plant_plot(i, selected_index, true):
				var fairy := _fairy_pos(0)
				beams.append({"from": fairy, "to": _plot_pos(i), "age": 0.0, "color": catalog[selected_index].color})
			return

func _harvest_plot(plot_idx: int, automatic: bool) -> void:
	if not plants.has(plot_idx):
		return
	var plant: Dictionary = plants[plot_idx]
	var data := catalog[int(plant.kind)]
	var gained := int(round(float(data.payout) * _payout_multiplier()))
	coins += gained
	plants.erase(plot_idx)
	_spawn_sparkles(_plot_pos(plot_idx), data.color, 28)
	_play_sfx("fairy" if automatic else "harvest")
	if automatic:
		beams.append({"from": _fairy_pos(plot_idx), "to": _plot_pos(plot_idx), "age": 0.0, "color": data.color})
		_flash("Fairy harvested %s +%d" % [data.name, gained])
	else:
		_flash("Harvested %s +%d glow" % [data.name, gained])

func _visible_catalog_size() -> int:
	if ascensions > 0:
		return 6
	if constellarium_unlocked:
		return 5
	return 4 if moonwell_unlocked else 3

func _plot_count() -> int:
	return BASE_PLOTS + EXTRA_PLOTS if ascensions >= 3 else BASE_PLOTS

func _auto_plant_unlocked() -> bool:
	return ascensions >= 2

func _lantern_cost() -> int:
	return 45 + lantern_level * 38

func _moonwell_cost() -> int:
	return 120

func _sprite_cost() -> int:
	return 180 + sprite_helpers * 165 + max(0, sprite_helpers - 6) * 260

func _constellarium_cost() -> int:
	return 1200

func _ascend_cost() -> int:
	return 6500 + ascensions * 4500

func _payout_multiplier() -> float:
	return 1.0 + float(stardust) * 0.18

func _growth_multiplier() -> float:
	return maxf(0.34, 1.0 - 0.12 * float(lantern_level) - 0.03 * float(stardust))

func _nearest_plot(pos: Vector2) -> int:
	var best := -1
	var best_d := 999999.0
	for i in range(_plot_count()):
		var p := _plot_pos(i)
		var d := p.distance_to(pos)
		if d < best_d:
			best = i
			best_d = d
	return best if best_d <= 40.0 else -1

func _plot_pos(i: int) -> Vector2:
	if i < BASE_PLOTS:
		var col := i % COLS
		var row := int(floor(float(i) / float(COLS)))
		return PLOT_START + Vector2(col * PLOT_SPACING, row * PLOT_SPACING)
	var e := i - BASE_PLOTS
	var side := e % 2
	var row2 := int(floor(float(e) / 2.0))
	var x := 62.0 if side == 0 else 478.0
	return Vector2(x, 222.0 + float(row2) * 82.0)

func _plant_stage(plant: Dictionary) -> int:
	var data := catalog[int(plant.kind)]
	var age := Time.get_ticks_msec() / 1000.0 - float(plant.planted_at)
	var adjusted_time := data.grow_time * _growth_multiplier()
	if age >= adjusted_time:
		return 2
	elif age >= adjusted_time * 0.45:
		return 1
	return 0

func _growth_ratio(plant: Dictionary) -> float:
	var data := catalog[int(plant.kind)]
	var age := Time.get_ticks_msec() / 1000.0 - float(plant.planted_at)
	return clampf(age / (data.grow_time * _growth_multiplier()), 0.0, 1.0)

func _flash(text: String) -> void:
	message = text
	message_timer = 2.5

func _show_big_prompt(title: String, body: String, footer: String) -> void:
	message = "%s — %s" % [title, footer]
	message_timer = 4.0
	active_prompt = {"age": 0.0, "title": title, "body": body, "footer": footer, "color": Color(0.86, 0.78, 1.0)}

func _spawn_sparkles(center: Vector2, color: Color, count: int) -> void:
	for i in range(count):
		var a := TAU * float(i) / float(maxi(1, count)) + randf_range(-0.35, 0.35)
		var spd := randf_range(28.0, 95.0)
		sparkles.append({"pos": center, "vel": Vector2(cos(a), sin(a)) * spd + Vector2(0, -20), "age": 0.0, "life": randf_range(0.45, 1.05), "color": color, "size": randf_range(1.8, 4.8)})

func _add_pulse(rect: Rect2, color: Color) -> void:
	pulse_cards.append({"kind": "rect", "age": 0.0, "rect": rect, "color": color})

func _draw() -> void:
	var s := _stage_scale()
	draw_set_transform(Vector2.ZERO, 0.0, s)
	_draw_background()
	_draw_plot_targets()
	_draw_plants()
	_draw_player()
	_draw_fairy_helpers()
	_draw_beams()
	_draw_sparkles()
	_draw_tap_rings()
	_draw_ui()
	_draw_card_pulses()
	_draw_active_prompt()
	_draw_ascension_fx()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_background() -> void:
	draw_texture_rect(BG, Rect2(0, 0, W, H), false)
	if ascensions >= 3:
		# Nebula Orchard side beds glow into existence after Ascension III.
		draw_rect(Rect2(0, 165, 92, 455), Color(0.25, 0.08, 0.34, 0.24), true)
		draw_rect(Rect2(448, 165, 92, 455), Color(0.25, 0.08, 0.34, 0.24), true)
	draw_rect(Rect2(0, 728, W, 232), Color(0.02, 0.015, 0.035, 0.54), true)

func _draw_plot_targets() -> void:
	for i in range(_plot_count()):
		var p := _plot_pos(i)
		var occupied := plants.has(i)
		var extra := i >= BASE_PLOTS
		var fill := Color(0.28, 0.16, 0.08, 0.18 if occupied else 0.34)
		if extra:
			fill = Color(0.24, 0.10, 0.35, 0.28 if occupied else 0.46)
		var ring := Color(1.0, 0.75, 0.34, 0.14 if occupied else 0.33)
		if extra:
			ring = Color(0.92, 0.48, 1.0, 0.24 if occupied else 0.50)
		draw_circle(p + Vector2(0, 6), 33, Color(0.02, 0.015, 0.01, 0.20))
		draw_circle(p, 30, fill)
		draw_arc(p, 31, 0, TAU, 48, ring, 2.0)

func _draw_plants() -> void:
	for i in plants.keys():
		var p := _plot_pos(int(i))
		var plant: Dictionary = plants[i]
		var stage := _plant_stage(plant)
		var ratio := _growth_ratio(plant)
		var data := catalog[int(plant.kind)]
		if stage == 0:
			_draw_tex_center(TEX_SEED, p + Vector2(0, -2), Vector2(40, 34), Color.WHITE)
			draw_arc(p, 34, -PI / 2.0, -PI / 2.0 + TAU * ratio, 32, data.color, 4.0)
		elif stage == 1:
			_draw_tex_center(TEX_SPROUT, p + Vector2(0, -12), Vector2(56, 54), Color.WHITE)
			draw_arc(p, 36, -PI / 2.0, -PI / 2.0 + TAU * ratio, 32, data.color, 4.0)
		else:
			var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.006 + float(i)) * 0.05
			draw_circle(p + Vector2(0, -16), 43 * pulse, Color(data.color.r, data.color.g, data.color.b, 0.26))
			_draw_tex_center(data.tex, p + Vector2(0, -28), Vector2(78, 94), data.color.lightened(0.2) if data.id in ["star", "nova", "sun"] else Color.WHITE)
			draw_arc(p + Vector2(0, -18), 48, 0, TAU, 48, Color(1, 1, 1, 0.36), 2.0)

func _draw_player() -> void:
	draw_circle(player_pos + Vector2(0, 18), 32, Color(0.02, 0.01, 0.04, 0.30))
	draw_circle(player_pos, 56, Color(1.0, 0.85, 0.32, 0.18))
	_draw_tex_center(TEX_SPIRIT, player_pos + Vector2(0, -14), Vector2(74, 78), Color.WHITE)

func _draw_fairy_helpers() -> void:
	if sprite_helpers <= 0:
		return
	var count := mini(sprite_helpers, 18)
	for i in range(count):
		var pos := _fairy_pos(i)
		var t := Time.get_ticks_msec() / 1000.0
		var fairy_color := Color(0.70 + 0.20 * sin(float(i)), 1.0, 0.78 + 0.18 * cos(float(i)), 0.95)
		draw_circle(pos, 18, Color(fairy_color.r, fairy_color.g, fairy_color.b, 0.17))
		var flap := sin(t * 12.0 + float(i))
		draw_circle(pos + Vector2(-7, -2 + flap * 2.5), 5.5, Color(0.85, 1.0, 1.0, 0.55))
		draw_circle(pos + Vector2(7, -2 - flap * 2.5), 5.5, Color(0.85, 1.0, 1.0, 0.55))
		draw_circle(pos, 4.5, fairy_color)
		draw_circle(pos + Vector2(0, -1), 1.5, Color.WHITE)
		draw_circle(pos - Vector2(7, 4), 2.0, Color(fairy_color.r, fairy_color.g, fairy_color.b, 0.45))
	if sprite_helpers > count:
		draw_string(ThemeDB.fallback_font, Vector2(386, 735), "+%d hidden fairies" % (sprite_helpers - count), HORIZONTAL_ALIGNMENT_LEFT, 140, 12, Color(0.78, 1.0, 0.86, 0.85))

func _fairy_pos(i: int) -> Vector2:
	var t := Time.get_ticks_msec() / 1000.0
	var count := maxi(1, mini(sprite_helpers, 18))
	var lane := float(i % 6)
	var ring := 70.0 + lane * 18.0
	var a := t * (1.25 + float(i % 3) * 0.18) + float(i) * TAU / float(count)
	var center := Vector2(270, 455)
	var pos := center + Vector2(cos(a) * ring * 1.25, sin(a * 1.37) * ring * 0.72)
	pos.y += sin(t * 6.0 + float(i)) * 7.0
	return pos

func _draw_beams() -> void:
	for b in beams:
		var a := 1.0 - float(b.age) / 0.45
		draw_line(b.from, b.to, Color(b.color.r, b.color.g, b.color.b, 0.50 * a), 3.0, true)
		draw_circle(b.to, 18.0 * a, Color(b.color.r, b.color.g, b.color.b, 0.28 * a))

func _draw_sparkles() -> void:
	for s in sparkles:
		var a := 1.0 - float(s.age) / float(s.life)
		draw_circle(s.pos, float(s.size) * a, Color(s.color.r, s.color.g, s.color.b, a))

func _draw_tap_rings() -> void:
	for r in tap_rings:
		var a := 1.0 - float(r.age) / 0.55
		draw_arc(r.pos, 12.0 + 42.0 * (1.0 - a), 0.0, TAU, 48, Color(1.0, 0.86, 0.42, a), 4.0)

func _draw_ui() -> void:
	draw_round_rect(Rect2(14, 14, 250, 84), 18, Color(0.035, 0.025, 0.075, 0.84), true)
	_draw_tex_center(TEX_LANTERN, Vector2(44, 56), Vector2(46, 60), Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(74, 41), "LANTERN HOLLOW", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(1.0, 0.86, 0.46))
	_draw_tex_center(TEX_COIN, Vector2(86, 66), Vector2(24, 24), Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(104, 70), "%d glow" % coins, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.95, 0.72))
	draw_string(ThemeDB.fallback_font, Vector2(104, 90), "%d dust  x%.2f" % [stardust, _payout_multiplier()], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.82, 0.92, 1.0))

	var msg_alpha := 1.0 if message_timer > 0.0 else 0.78
	draw_round_rect(Rect2(278, 22, 244, 72), 18, Color(0.035, 0.025, 0.075, 0.74), true)
	draw_string(ThemeDB.fallback_font, Vector2(294, 52), _next_goal_text(), HORIZONTAL_ALIGNMENT_LEFT, 210, 13, Color(1.0, 0.88, 0.62, 0.95))
	draw_string(ThemeDB.fallback_font, Vector2(294, 76), message, HORIZONTAL_ALIGNMENT_LEFT, 210, 12, Color(0.94, 0.88, 1.0, msg_alpha))

	_draw_upgrade_strip()
	_draw_seed_selector()

func _next_goal_text() -> String:
	if not moonwell_unlocked:
		return "Goal: build Moonwell (120)"
	if not constellarium_unlocked:
		return "Goal: light Stars (1200)"
	if ascensions == 0:
		return "Goal: Ascend (6500)"
	if ascensions == 1:
		return "Goal: Ascend II = auto-plant"
	if ascensions == 2:
		return "Goal: Ascend III = +10 beds"
	return "Goal: stack Stardust"

func _draw_upgrade_strip() -> void:
	for i in range(4):
		var rect := _upgrade_rect(i)
		var label := ""
		var sub := ""
		var color := Color(1.0, 0.82, 0.30)
		if i == 0:
			label = "Lantern %d" % lantern_level
			sub = "%d faster" % _lantern_cost()
			color = Color(1.0, 0.78, 0.28)
		elif i == 1:
			label = "Moonwell" if not moonwell_unlocked else "Stars"
			sub = "%d Starvine" % _moonwell_cost() if not moonwell_unlocked else ("%d Nova" % _constellarium_cost() if not constellarium_unlocked else "Nova online")
			color = Color(0.72, 0.70, 1.0)
		elif i == 2:
			label = "Fairies %d" % sprite_helpers
			sub = "%d harvest" % _sprite_cost() if not _auto_plant_unlocked() else "%d plant+harv" % _sprite_cost()
			color = Color(0.62, 1.0, 0.78)
		else:
			label = "Ascend %d" % ascensions
			sub = "%d dust" % _ascend_cost()
			color = Color(1.0, 0.58, 0.95)
		var bg := Color(color.r * 0.16, color.g * 0.16, color.b * 0.16, 0.88)
		draw_round_rect(rect, 14, bg, true)
		draw_arc(rect.position + Vector2(22, 28), 18, 0, TAU, 28, color, 3.0)
		if i == 0:
			_draw_tex_center(TEX_LANTERN, rect.position + Vector2(22, 28), Vector2(26, 34), Color.WHITE)
		elif i == 1:
			draw_circle(rect.position + Vector2(22, 28), 14, Color(0.55, 0.65, 1.0, 0.8))
			draw_circle(rect.position + Vector2(22, 28), 6, Color(0.95, 0.95, 1.0, 0.95))
		elif i == 2:
			_draw_tex_center(TEX_SPIRIT, rect.position + Vector2(22, 28), Vector2(30, 30), Color.WHITE)
		else:
			draw_circle(rect.position + Vector2(22, 28), 14, Color(1.0, 0.45, 0.95, 0.75))
			draw_arc(rect.position + Vector2(22, 28), 20, 0, TAU, 5, Color.WHITE, 2.0)
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(43, 27), label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 45, 12, Color.WHITE)
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(43, 48), sub, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 45, 10, Color(1.0, 0.92, 0.68))

func _upgrade_rect(i: int) -> Rect2:
	var w := (W - 42.0) / 4.0
	return Rect2(8.0 + float(i) * (w + 8.0), 748, w, 62)

func _draw_seed_selector() -> void:
	draw_round_rect(Rect2(0, 820, W, 140), 24, Color(0.035, 0.025, 0.075, 0.94), true)
	var visible_count := _visible_catalog_size()
	for i in range(visible_count):
		var data := catalog[i]
		var rect := _seed_rect(i, visible_count)
		var bg := Color(0.13, 0.10, 0.19, 0.88)
		if i == selected_index:
			bg = Color(data.color.r * 0.22, data.color.g * 0.22, data.color.b * 0.22, 0.96)
		draw_round_rect(rect, 18, bg, true)
		draw_arc(rect.get_center() + Vector2(0, -18), 34, 0, TAU, 44, data.color, 3.0)
		_draw_tex_center(data.tex, rect.get_center() + Vector2(0, -24), Vector2(50, 54), data.color.lightened(0.2) if data.id in ["star", "nova", "sun"] else Color.WHITE)
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(8, 72), data.name, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 16, 12, Color.WHITE)
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(8, 94), "%d→%d" % [data.cost, int(round(float(data.payout) * _payout_multiplier()))], HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 16, 12, Color(1.0, 0.86, 0.48))

func _seed_rect(i: int, visible_count: int) -> Rect2:
	var button_w := W / float(visible_count)
	return Rect2(float(i) * button_w + 8.0, 840, button_w - 16.0, 104)


func _draw_active_prompt() -> void:
	if active_prompt.is_empty():
		return
	var age := float(active_prompt.get("age", 0.0))
	var appear := clampf(age / 0.18, 0.0, 1.0)
	# Dim the game behind the explanation so it reads like an actual tutorial modal.
	draw_rect(Rect2(0, 0, W, H), Color(0.015, 0.01, 0.035, 0.44 * appear), true)
	var panel := Rect2(34, 118, 472, 198)
	var color: Color = active_prompt.color
	draw_round_rect(panel, 26, Color(0.035, 0.025, 0.075, 0.94 * appear), true)
	draw_round_rect(panel.grow(3), 28, Color(color.r, color.g, color.b, 0.18 * appear), true)
	draw_arc(panel.position + Vector2(36, 38), 25, 0, TAU, 34, color, 3.0)
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(76, 43), str(active_prompt.title), HORIZONTAL_ALIGNMENT_LEFT, 360, 25, Color(1, 1, 1, appear))
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(30, 88), str(active_prompt.body), HORIZONTAL_ALIGNMENT_LEFT, 412, 16, Color(0.92, 0.88, 1.0, appear))
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(30, 156), str(active_prompt.footer), HORIZONTAL_ALIGNMENT_LEFT, 412, 15, Color(1.0, 0.88, 0.52, appear))
	var blink := 0.72 + 0.28 * sin(Time.get_ticks_msec() * 0.006)
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(144, 185), "Tap anywhere to continue", HORIZONTAL_ALIGNMENT_LEFT, 230, 14, Color(0.78, 1.0, 0.90, blink * appear))

func _draw_card_pulses() -> void:
	for p in pulse_cards:
		var a := 1.0 - float(p.age) / (0.65 if p.kind == "rect" else 4.0)
		if p.kind == "rect":
			var rect: Rect2 = p.rect
			rect = rect.grow(10.0 * (1.0 - a))
			draw_round_rect(rect, 20, Color(p.color.r, p.color.g, p.color.b, 0.26 * a), true)
		elif p.kind == "prompt":
			var panel := Rect2(38, 130, 464, 142)
			draw_round_rect(panel, 24, Color(0.035, 0.025, 0.075, 0.88 * minf(1.0, a + 0.25)), true)
			draw_arc(panel.position + Vector2(32, 34), 24, 0, TAU, 32, p.color, 3.0)
			draw_string(ThemeDB.fallback_font, panel.position + Vector2(70, 38), p.title, HORIZONTAL_ALIGNMENT_LEFT, 360, 24, Color.WHITE)
			draw_string(ThemeDB.fallback_font, panel.position + Vector2(28, 78), p.body, HORIZONTAL_ALIGNMENT_LEFT, 410, 15, Color(0.92, 0.88, 1.0))
			draw_string(ThemeDB.fallback_font, panel.position + Vector2(28, 124), p.footer, HORIZONTAL_ALIGNMENT_LEFT, 410, 14, Color(1.0, 0.88, 0.52))

func _draw_ascension_fx() -> void:
	if ascension_fx <= 0.0:
		return
	var a := ascension_fx / 2.8
	draw_circle(Vector2(270, 390), 290.0 * (1.0 - a), Color(1.0, 0.50, 0.95, 0.10 * a))
	draw_arc(Vector2(270, 390), 130.0 + 80.0 * (1.0 - a), 0, TAU, 80, Color(1.0, 0.72, 1.0, 0.55 * a), 5.0)

func _draw_tex_center(tex: Texture2D, center: Vector2, max_size: Vector2, tint: Color = Color.WHITE) -> void:
	if tex == null:
		return
	var src_size: Vector2 = tex.get_size()
	if src_size.x <= 0.0 or src_size.y <= 0.0:
		return
	var s: float = min(max_size.x / src_size.x, max_size.y / src_size.y)
	var final_size: Vector2 = src_size * s
	var rect := Rect2(center - final_size * 0.5, final_size)
	draw_texture_rect(tex, rect, false, tint)

func draw_round_rect(rect: Rect2, radius: float, color: Color, filled: bool = true) -> void:
	if not filled:
		draw_rect(rect, color, false, 2.0)
		return
	draw_rect(Rect2(rect.position + Vector2(radius, 0), Vector2(rect.size.x - radius * 2.0, rect.size.y)), color, true)
	draw_rect(Rect2(rect.position + Vector2(0, radius), Vector2(rect.size.x, rect.size.y - radius * 2.0)), color, true)
	draw_circle(rect.position + Vector2(radius, radius), radius, color)
	draw_circle(rect.position + Vector2(rect.size.x - radius, radius), radius, color)
	draw_circle(rect.position + Vector2(radius, rect.size.y - radius), radius, color)
	draw_circle(rect.position + Vector2(rect.size.x - radius, rect.size.y - radius), radius, color)
