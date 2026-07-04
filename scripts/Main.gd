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

# Web-safe atmosphere toggles. Each feature ships in its own commit.
const ATM_FIREFLIES_ENABLED := true
const ATM_FIREFLY_COUNT := 12
const ATM_DUST_ENABLED := true
const ATM_DUST_COUNT := 34
const ATM_GARDEN_EDGE_GLOW_ENABLED := true
const ATM_BLOOM_READY_PULSE_ENABLED := true
const ATM_FAIRY_TRAILS_ENABLED := true
const ATM_UPGRADE_GLOWS_ENABLED := true
const ATM_ASCENSION_WAVE_ENABLED := true

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
var message := "Tap an empty bed to plant. Tap a full bloom to harvest glow."
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
var is_dragging := false
var pointer_down := false
var drag_start := Vector2.ZERO
var drag_last := Vector2.ZERO
const DRAG_THRESHOLD := 14.0

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
	_show_big_prompt("How to play", "1. Choose a flower at the bottom.\n2. Tap an empty bed to plant.\n3. Tap a full bloom to harvest glow.\n4. Buy upgrades, then Ascend for Stardust.", "First goal: plant Sparkbuds until you can afford Moonblossom.")
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	var to_target := player_target - player_pos
	if to_target.length() > 3.0:
		player_pos += to_target.normalized() * min(PLAYER_SPEED * delta, to_target.length())

	# While dragging, plant/harvest any bed the spirit passes over.
	if is_dragging and pointer_down:
		var plot_idx := _nearest_plot(player_pos)
		if plot_idx != -1:
			if plants.has(plot_idx):
				var plant: Dictionary = plants[plot_idx]
				if _plant_stage(plant) >= 2:
					_harvest_plot(plot_idx, false)
			else:
				_plant_plot(plot_idx, selected_index, false)

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
	tap_rings = tap_rings.filter(func(r): return r.age < 0.38)
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
		_show_big_prompt("Upgrade available: Lantern", "Lanterns make every planted flower grow faster.\nBuy one whenever crops feel slow or you are waiting around.", "Tap the Lantern card in the upgrade row.")
	if not seen_moonwell_hint and coins >= _moonwell_cost() and not moonwell_unlocked:
		seen_moonwell_hint = true
		_show_big_prompt("Next unlock: Moonwell", "Moonwell opens the next tier of flowers: Starvine.\nStarvine earns much more glow than Emberlily, so this is your first big goal.", "Save 120 glow, then tap the Moonwell card.")
	if moonwell_unlocked and not seen_constellarium_hint and coins >= _constellarium_cost() and not constellarium_unlocked:
		seen_constellarium_hint = true
		_show_big_prompt("Next unlock: Constellarium", "The Constellarium unlocks Nova Lotus.\nNova Lotus is expensive, slow, and powerful. Use it to reach Ascension.", "Save 1200 glow, then tap the Stars card.")
	if constellarium_unlocked and not seen_ascend_hint and coins >= 3000:
		seen_ascend_hint = true
		_show_big_prompt("Ascension is near", "Ascension resets flowers and upgrades, but gives Stardust.\nStardust is permanent: every future run pays more and grows faster.", "At 6500 glow, tap Ascend.")

func _unhandled_input(event: InputEvent) -> void:
	# Mouse (desktop)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_unlock_audio_from_gesture()
			pointer_down = true
			is_dragging = false
			drag_start = event.position
			drag_last = event.position
		else:
			if pointer_down and not is_dragging:
				_handle_tap(event.position)
			pointer_down = false
			is_dragging = false
	elif event is InputEventMouseMotion and pointer_down:
		drag_last = event.position
		if not is_dragging and event.position.distance_to(drag_start) > DRAG_THRESHOLD:
			is_dragging = true
		if is_dragging:
			player_target = _screen_to_stage(event.position)

	# Touch (mobile)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_unlock_audio_from_gesture()
			pointer_down = true
			is_dragging = false
			drag_start = event.position
			drag_last = event.position
		else:
			if pointer_down and not is_dragging:
				_handle_tap(event.position)
			pointer_down = false
			is_dragging = false
	elif event is InputEventScreenDrag:
		drag_last = event.position
		if not is_dragging and event.position.distance_to(drag_start) > DRAG_THRESHOLD:
			is_dragging = true
		if is_dragging:
			player_target = _screen_to_stage(event.position)

func _handle_tap(screen_pos: Vector2) -> void:
	if not active_prompt.is_empty():
		# Only dismiss when the player taps the "Got it!" button.
		var stage_pos := _screen_to_stage(screen_pos)
		if _prompt_button_rect().has_point(stage_pos):
			active_prompt.clear()
		return

	var pos := _screen_to_stage(screen_pos)
	player_target = pos
	# Generic touch feedback was too busy with the new garden polish.
	# Keep rings only for actual plant / harvest moments.

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
	var burst_pos := _plot_pos(plot_idx)
	_spawn_sparkles(burst_pos, selected.color, 22)
	tap_rings.append({"pos": burst_pos, "age": 0.0, "color": selected.color.lightened(0.12), "scale": 0.62})
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
		_show_big_prompt("Lantern upgraded", "Every flower now grows faster.\nThis stacks, so more Lantern levels mean less waiting between harvests.", "Lantern level %d active." % lantern_level)
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
			_show_big_prompt("Moonwell built", "Starvine is now unlocked in the flower bar.\nIt costs more than Emberlily, but pays much more glow per harvest.", "Select Starvine, plant it, then save for Stars.")
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
			_show_big_prompt("Constellarium lit", "Nova Lotus is now unlocked.\nUse Nova Lotus harvests to climb from normal upgrades into your first Ascension.", "Plant Nova Lotus, then save 6500 glow.")
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
			_show_big_prompt("Fairies learned to plant", "Because you reached Ascension II, fairies can plant too.\nThey fill empty beds with your selected flower when you have enough glow.", "Choose the flower you want automated.")
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
			_show_big_prompt("Ascension I complete", "+%d Stardust earned.\nSunseed is unlocked. Stardust is permanent, so all future flowers pay more and grow faster." % earned, "Rebuild with Sunseed and reach Ascension II.")
		elif ascensions == 2:
			seen_auto_plant_hint = true
			_show_big_prompt("Ascension II complete", "+%d Stardust earned.\nFairies can now auto-plant your selected flower into empty beds." % earned, "Buy fairies, pick a flower, and let them garden.")
		elif ascensions == 3:
			seen_orchard_hint = true
			_show_big_prompt("Ascension III complete", "+%d Stardust earned.\nNebula Orchard unlocked: ten extra side beds now appear on the garden edges." % earned, "More beds means bigger fairy-powered gardens.")
		else:
			_show_big_prompt("Ascension %d complete" % ascensions, "+%d Stardust earned.\nEach Ascension makes future loops richer, faster, and easier to automate." % earned, "Keep stacking Stardust for bigger numbers.")

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
	var burst_pos := _plot_pos(plot_idx)
	_spawn_sparkles(burst_pos, data.color, 44)
	_spawn_sparkles(burst_pos + Vector2(0, -18), Color(1.0, 0.92, 0.55), 18)
	tap_rings.append({"pos": burst_pos, "age": 0.0, "color": data.color.lightened(0.18), "scale": 0.78})
	_play_sfx("fairy" if automatic else "harvest")
	if automatic:
		beams.append({"from": _fairy_pos(plot_idx), "to": _plot_pos(plot_idx), "age": 0.0, "color": data.color})
		_flash("Fairy harvested %s: +%d glow" % [data.name, gained])
	else:
		_flash("Harvested %s: +%d glow" % [data.name, gained])

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
	message = footer
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
	_draw_garden_edge_glow()
	_draw_fireflies()
	_draw_magic_dust()
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

func _draw_fireflies() -> void:
	if not ATM_FIREFLIES_ENABLED:
		return
	var t := Time.get_ticks_msec() * 0.001
	for i in range(ATM_FIREFLY_COUNT):
		var seed := float(i) * 7.31
		var x := W * 0.5 + sin(t * 0.18 + seed) * (170.0 + 22.0 * sin(t * 0.07 + seed))
		var y := 260.0 + cos(t * 0.23 + seed * 1.3) * 130.0 + sin(t * 0.4 + seed) * 16.0
		var breathe := 0.5 + 0.5 * sin(t * 1.6 + seed * 0.7)
		var glow := Color(1.0, 0.82, 0.36)
		draw_circle(Vector2(x, y), 7.0, Color(glow.r, glow.g, glow.b, 0.16 + 0.12 * breathe))
		draw_circle(Vector2(x, y), 3.2, Color(1.0, 0.94, 0.68, 0.42 + 0.24 * breathe))

func _draw_garden_edge_glow() -> void:
	if not ATM_GARDEN_EDGE_GLOW_ENABLED:
		return
	var t := Time.get_ticks_msec() * 0.001
	var breathe := 0.5 + 0.5 * sin(t * 0.55)
	draw_rect(Rect2(0, 112, 48, 590), Color(0.19, 0.06, 0.28, 0.12 + 0.05 * breathe), true)
	draw_rect(Rect2(W - 48, 112, 48, 590), Color(0.19, 0.06, 0.28, 0.12 + 0.05 * breathe), true)
	draw_rect(Rect2(0, 110, W, 32), Color(0.45, 0.24, 0.08, 0.04 + 0.025 * breathe), true)
	for i in range(5):
		var y := 170.0 + float(i) * 98.0 + sin(t * 0.7 + float(i)) * 10.0
		var c := Color(0.95, 0.38, 1.0, 0.045 + 0.025 * sin(t * 0.8 + float(i) * 1.3))
		draw_circle(Vector2(24, y), 38.0 + 4.0 * breathe, c)
		draw_circle(Vector2(W - 24, y + 22.0), 34.0 + 3.0 * breathe, c)

func _draw_magic_dust() -> void:
	if not ATM_DUST_ENABLED:
		return
	var t := Time.get_ticks_msec() * 0.001
	for i in range(ATM_DUST_COUNT):
		var seed := float(i) * 19.17
		var lane := fposmod(seed * 0.137, 1.0)
		var x := 28.0 + lane * (W - 56.0) + sin(t * 0.23 + seed) * 14.0
		var y := 122.0 + fposmod(seed + t * (11.0 + float(i % 5) * 2.2), 600.0)
		var twinkle := 0.45 + 0.55 * sin(t * 1.65 + seed)
		var r := 1.1 + float(i % 3) * 0.45 + twinkle * 0.55
		var col := Color(0.95, 0.88, 1.0, 0.10 + 0.10 * twinkle)
		draw_circle(Vector2(x, y), r + 3.0, Color(col.r, col.g, col.b, col.a * 0.16))
		draw_circle(Vector2(x, y), r, col)

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
			if ATM_BLOOM_READY_PULSE_ENABLED and ratio > 0.80:
				var almost := clampf((ratio - 0.80) / 0.20, 0.0, 1.0)
				draw_circle(p + Vector2(0, -12), 42.0 + 7.0 * almost, Color(data.color.r, data.color.g, data.color.b, 0.18 * almost))
				draw_arc(p + Vector2(0, -12), 45.0 + 5.0 * almost, 0.0, TAU, 48, Color(1.0, 0.92, 0.58, 0.32 * almost), 2.0)
		else:
			var t := Time.get_ticks_msec() * 0.001
			var pulse := 1.0 + sin(t * 6.0 + float(i)) * 0.05
			var ready_breathe := 0.5 + 0.5 * sin(t * 3.2 + float(i))
			if ATM_BLOOM_READY_PULSE_ENABLED:
				draw_circle(p + Vector2(0, -18), 66.0 + ready_breathe * 8.0, Color(data.color.r, data.color.g, data.color.b, 0.08 + 0.06 * ready_breathe))
				draw_arc(p + Vector2(0, -18), 54.0 + ready_breathe * 5.0, 0.0, TAU, 56, Color(1.0, 0.91, 0.58, 0.42 + 0.18 * ready_breathe), 2.5)
				draw_string(ThemeDB.fallback_font, p + Vector2(-22, -72), "READY", HORIZONTAL_ALIGNMENT_LEFT, 52, 10, Color(1.0, 0.90, 0.48, 0.76 + 0.20 * ready_breathe))
			draw_circle(p + Vector2(0, -16), 43 * pulse, Color(data.color.r, data.color.g, data.color.b, 0.26))
			_draw_tex_center(data.tex, p + Vector2(0, -28), Vector2(78, 94), data.color.lightened(0.2) if data.id in ["star", "nova", "sun"] else Color.WHITE)
			draw_arc(p + Vector2(0, -18), 48, 0, TAU, 48, Color(1, 1, 1, 0.36), 2.0)

func _draw_player() -> void:
	var t := Time.get_ticks_msec() * 0.001
	var pulse := 0.5 + 0.5 * sin(t * 2.1)
	draw_circle(player_pos + Vector2(0, 18), 34, Color(0.02, 0.01, 0.04, 0.32))
	draw_circle(player_pos, 78 + 5 * pulse, Color(1.0, 0.70, 0.22, 0.055))
	draw_circle(player_pos, 58 + 3 * pulse, Color(1.0, 0.85, 0.32, 0.16))
	draw_circle(player_pos + Vector2(0, -8), 34 + 2 * pulse, Color(0.75, 0.92, 1.0, 0.08))
	_draw_tex_center(TEX_SPIRIT, player_pos + Vector2(0, -14), Vector2(74, 78), Color.WHITE)
	draw_arc(player_pos + Vector2(0, -6), 46 + 2 * pulse, -PI * 0.15, TAU - PI * 0.15, 64, Color(1.0, 0.90, 0.56, 0.18), 2.0)

func _draw_fairy_helpers() -> void:
	if sprite_helpers <= 0:
		return
	var count := mini(sprite_helpers, 18)
	for i in range(count):
		var pos := _fairy_pos(i)
		var t := Time.get_ticks_msec() / 1000.0
		var fairy_color := Color(0.70 + 0.20 * sin(float(i)), 1.0, 0.78 + 0.18 * cos(float(i)), 0.95)
		if ATM_FAIRY_TRAILS_ENABLED:
			for j in range(3):
				var lag := float(j + 1)
				var drift := Vector2(cos(t * 2.4 + float(i) + lag), sin(t * 2.0 + float(i) * 0.7 + lag)) * (7.0 + lag * 5.0)
				draw_circle(pos - drift, 4.0 - lag * 0.65, Color(fairy_color.r, fairy_color.g, fairy_color.b, 0.18 - lag * 0.035))
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
		var from_pos: Vector2 = b.from
		var to_pos: Vector2 = b.to
		var beam_color: Color = b.color
		if ATM_FAIRY_TRAILS_ENABLED:
			for i in range(1, 4):
				var k := float(i) / 4.0
				var shimmer: Vector2 = from_pos.lerp(to_pos, k)
				var wave := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012 + k * TAU)
				draw_circle(shimmer, 7.0 + 3.0 * wave, Color(beam_color.r, beam_color.g, beam_color.b, 0.15 * a))
		draw_line(from_pos, to_pos, Color(beam_color.r, beam_color.g, beam_color.b, 0.50 * a), 3.0, true)
		draw_circle(to_pos, 18.0 * a, Color(beam_color.r, beam_color.g, beam_color.b, 0.28 * a))

func _draw_sparkles() -> void:
	for s in sparkles:
		var a := 1.0 - float(s.age) / float(s.life)
		draw_circle(s.pos, float(s.size) * a, Color(s.color.r, s.color.g, s.color.b, a))

func _draw_tap_rings() -> void:
	for r in tap_rings:
		var a := 1.0 - float(r.age) / 0.38
		var color: Color = r.get("color", Color(1.0, 0.86, 0.42))
		var scale: float = float(r.get("scale", 1.0))
		draw_circle(r.pos, 8.0 * scale * a, Color(color.r, color.g, color.b, 0.08 * a))
		draw_arc(r.pos, (10.0 + 26.0 * (1.0 - a)) * scale, 0.0, TAU, 48, Color(color.r, color.g, color.b, 0.34 * a), 2.0 * scale)

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
		return "Next: save 120 glow for Moonwell"
	if not constellarium_unlocked:
		return "Next: save 1200 glow for Stars"
	if ascensions == 0:
		return "Next: save 6500 glow to Ascend"
	if ascensions == 1:
		return "Next: Ascend II unlocks auto-plant"
	if ascensions == 2:
		return "Next: Ascend III adds 10 beds"
	return "Next: stack Stardust"

func _draw_upgrade_strip() -> void:
	for i in range(4):
		var rect := _upgrade_rect(i)
		var label := ""
		var sub := ""
		var color := Color(1.0, 0.82, 0.30)
		if i == 0:
			label = "Lantern %d" % lantern_level
			sub = "%d glow - speed" % _lantern_cost()
			color = Color(1.0, 0.78, 0.28)
		elif i == 1:
			label = "Moonwell" if not moonwell_unlocked else "Stars"
			sub = "%d glow - Starvine" % _moonwell_cost() if not moonwell_unlocked else ("%d glow - Nova" % _constellarium_cost() if not constellarium_unlocked else "Nova unlocked")
			color = Color(0.72, 0.70, 1.0)
		elif i == 2:
			label = "Fairies %d" % sprite_helpers
			sub = "%d glow - harvest" % _sprite_cost() if not _auto_plant_unlocked() else "%d glow - plant" % _sprite_cost()
			color = Color(0.62, 1.0, 0.78)
		else:
			label = "Ascend %d" % ascensions
			sub = "%d glow - dust" % _ascend_cost()
			color = Color(1.0, 0.58, 0.95)
		var bg := Color(color.r * 0.16, color.g * 0.16, color.b * 0.16, 0.88)
		if ATM_UPGRADE_GLOWS_ENABLED:
			var glow_on := false
			if i == 0:
				glow_on = lantern_level > 0 or coins >= _lantern_cost()
			elif i == 1:
				var next_cost := _moonwell_cost() if not moonwell_unlocked else (_constellarium_cost() if not constellarium_unlocked else 999999999)
				glow_on = moonwell_unlocked or constellarium_unlocked or coins >= next_cost
			elif i == 2:
				glow_on = sprite_helpers > 0 or coins >= _sprite_cost()
			else:
				glow_on = ascensions > 0 or coins >= _ascend_cost()
			if glow_on:
				var card_pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.0025 + float(i))
				draw_round_rect(rect.grow(4.0 + card_pulse * 3.0), 20, Color(color.r, color.g, color.b, 0.08 + 0.06 * card_pulse), true)
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
	draw_string(ThemeDB.fallback_font, Vector2(18, 836), "Flowers: tap to choose.  Cost / harvest shown below each flower.", HORIZONTAL_ALIGNMENT_LEFT, 504, 10, Color(0.88, 0.86, 1.0, 0.72))
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
		# Avoid the Unicode arrow here: Godot's web fallback font renders it as a
		# missing-glyph box ("21/92") on iPhone Safari.
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(8, 94), "%d  /  %d" % [data.cost, int(round(float(data.payout) * _payout_multiplier()))], HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 16, 12, Color(1.0, 0.86, 0.48))

func _seed_rect(i: int, visible_count: int) -> Rect2:
	var button_w := W / float(visible_count)
	return Rect2(float(i) * button_w + 8.0, 840, button_w - 16.0, 104)


const PROMPT_PANEL := Rect2(40, 90, 460, 340)

func _prompt_button_rect() -> Rect2:
	var cx := PROMPT_PANEL.position.x + PROMPT_PANEL.size.x * 0.5
	var by := PROMPT_PANEL.position.y + PROMPT_PANEL.size.y - 52.0
	return Rect2(cx - 75.0, by, 150.0, 38.0)

func _draw_active_prompt() -> void:
	if active_prompt.is_empty():
		return
	var age := float(active_prompt.get("age", 0.0))
	var appear := clampf(age / 0.22, 0.0, 1.0)
	var t := Time.get_ticks_msec() * 0.001
	var color: Color = active_prompt.color
	var panel := PROMPT_PANEL

	# Dim the garden behind so the card pops.
	draw_rect(Rect2(0, 0, W, H), Color(0.01, 0.008, 0.03, 0.52 * appear), true)

	# Soft breathing glow halo behind the card.
	var breathe := 0.85 + 0.15 * sin(t * 1.8)
	for i in range(4):
		var grow_amt := 8.0 + float(i) * 9.0
		var halo_a := (0.16 - float(i) * 0.035) * appear * breathe
		draw_round_rect(panel.grow(grow_amt), 30.0 + float(i) * 6.0, Color(color.r, color.g, color.b, halo_a), true)

	# Card body: warm deep indigo with a gentle top-to-bottom gradient feel.
	draw_round_rect(panel.grow(2), 26, Color(color.r * 0.5, color.g * 0.5, color.b * 0.6, 0.30 * appear), true)
	draw_round_rect(panel, 22, Color(0.06, 0.04, 0.12, 0.97 * appear), true)

	# Top accent strip: warm golden band with the title color tinted in.
	var strip := Rect2(panel.position.x + 14, panel.position.y + 14, panel.size.x - 28, 40)
	draw_round_rect(strip, 16, Color(color.r * 0.35, color.g * 0.30, color.b * 0.45, 0.55 * appear), true)
	# Tiny lantern icon dot on the strip.
	draw_circle(Vector2(strip.position.x + 22, strip.get_center().y), 7.0, Color(1.0, 0.84, 0.40, 0.92 * appear))
	draw_circle(Vector2(strip.position.x + 22, strip.get_center().y), 11.0, Color(1.0, 0.78, 0.36, 0.22 * appear))
	draw_string(ThemeDB.fallback_font, Vector2(strip.position.x + 42, strip.get_center().y + 9), str(active_prompt.title), HORIZONTAL_ALIGNMENT_LEFT, strip.size.x - 56, 22, Color(1.0, 0.94, 0.80, appear))

	# Body text.
	_draw_text_lines(str(active_prompt.body), panel.position + Vector2(28, 82), 23.0, 15, Color(0.90, 0.86, 1.0, appear), panel.size.x - 56)

	# Shimmering divider.
	var div_a := (0.30 + 0.12 * sin(t * 2.5)) * appear
	draw_rect(Rect2(panel.position + Vector2(28, 232), Vector2(panel.size.x - 56, 1.5)), Color(1.0, 0.84, 0.52, div_a), true)

	# Footer text.
	_draw_text_lines(str(active_prompt.footer), panel.position + Vector2(28, 258), 21.0, 14, Color(1.0, 0.86, 0.50, appear), panel.size.x - 56)

	# "Got it!" button: pill-shaped, pulsing softly.
	var btn := _prompt_button_rect()
	var btn_pulse := 0.88 + 0.12 * sin(t * 3.0)
	draw_round_rect(btn.grow(5), 22, Color(0.45, 1.0, 0.72, 0.18 * appear * btn_pulse), true)
	draw_round_rect(btn, 18, Color(0.20, 0.55, 0.36, 0.95 * appear), true)
	draw_round_rect(Rect2(btn.position, Vector2(btn.size.x, btn.size.y * 0.5)), 18, Color(0.30, 0.72, 0.48, 0.45 * appear), true)
	draw_string(ThemeDB.fallback_font, btn.get_center() + Vector2(-26, 6), "Got it!", HORIZONTAL_ALIGNMENT_LEFT, 80, 16, Color(0.92, 1.0, 0.95, appear))

func _draw_card_pulses() -> void:
	for p in pulse_cards:
		var a := 1.0 - float(p.age) / (0.65 if p.kind == "rect" else 4.0)
		if p.kind == "rect":
			var rect: Rect2 = p.rect
			rect = rect.grow(10.0 * (1.0 - a))
			draw_round_rect(rect, 20, Color(p.color.r, p.color.g, p.color.b, 0.26 * a), true)
		elif p.kind == "prompt":
			var panel := Rect2(38, 130, 464, 142)
			draw_rect(panel.grow(3), Color(p.color.r, p.color.g, p.color.b, 0.18 * minf(1.0, a + 0.25)), true)
			draw_rect(panel, Color(0.035, 0.025, 0.075, 0.88 * minf(1.0, a + 0.25)), true)
			draw_rect(Rect2(panel.position, Vector2(7, panel.size.y)), Color(p.color.r, p.color.g, p.color.b, 0.58 * a), true)
			draw_string(ThemeDB.fallback_font, panel.position + Vector2(24, 38), p.title, HORIZONTAL_ALIGNMENT_LEFT, 390, 24, Color.WHITE)
			draw_string(ThemeDB.fallback_font, panel.position + Vector2(24, 78), p.body, HORIZONTAL_ALIGNMENT_LEFT, 410, 15, Color(0.92, 0.88, 1.0))
			draw_string(ThemeDB.fallback_font, panel.position + Vector2(24, 124), p.footer, HORIZONTAL_ALIGNMENT_LEFT, 410, 14, Color(1.0, 0.88, 0.52))

func _draw_ascension_fx() -> void:
	if ascension_fx <= 0.0:
		return
	var a := ascension_fx / 2.8
	if ATM_ASCENSION_WAVE_ENABLED:
		var center := Vector2(270, 390)
		draw_circle(center, 320.0 * (1.0 - a), Color(1.0, 0.50, 0.95, 0.12 * a))
		for i in range(4):
			var k := float(i) / 4.0
			var radius := 90.0 + 250.0 * (1.0 - a) + k * 34.0
			var alpha := (0.46 - k * 0.08) * a
			draw_arc(center, radius, 0, TAU, 96, Color(1.0, 0.72 + k * 0.05, 1.0, alpha), 5.0 - k * 0.55)
		for i in range(14):
			var ang := float(i) * TAU / 14.0 + (1.0 - a) * 1.7
			var pos := center + Vector2(cos(ang), sin(ang)) * (80.0 + 220.0 * (1.0 - a))
			draw_circle(pos, 4.0 + 4.0 * a, Color(1.0, 0.90, 0.56, 0.32 * a))
	else:
		draw_circle(Vector2(270, 390), 290.0 * (1.0 - a), Color(1.0, 0.50, 0.95, 0.10 * a))
		draw_arc(Vector2(270, 390), 130.0 + 80.0 * (1.0 - a), 0, TAU, 80, Color(1.0, 0.72, 1.0, 0.55 * a), 5.0)

func _draw_text_lines(text: String, pos: Vector2, line_height: float, font_size: int, color: Color, width: float) -> void:
	var y := pos.y
	# Godot's low-level draw_string does not wrap reliably in the web export, so
	# wrap by words before drawing. Approximate chars-per-line keeps iPhone safe.
	var max_chars: int = maxi(24, int(width / maxf(7.0, float(font_size) * 0.78)))
	for raw_line in text.split("\n"):
		var line := ""
		for word in raw_line.split(" "):
			var candidate := word if line.is_empty() else line + " " + word
			if candidate.length() > max_chars and not line.is_empty():
				draw_string(ThemeDB.fallback_font, Vector2(pos.x, y), line, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, color)
				y += line_height
				line = word
			else:
				line = candidate
		if not line.is_empty():
			draw_string(ThemeDB.fallback_font, Vector2(pos.x, y), line, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, color)
			y += line_height

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
	radius = minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	if radius <= 1.0:
		draw_rect(rect, color, true)
		return
	# Draw the rounded rectangle as a single filled polygon.
	# The old approach (overlapping rects + draw_circle at each corner) left
	# visible circle artifacts at the four corners on iPhone Safari's canvas
	# renderer because anti-aliasing / alpha blending differed between the
	# circle fills and the rect fills. A single polygon has no seams.
	var p := rect.position
	var s := rect.size
	var r := radius
	var pts := PackedVector2Array()
	var n := 10  # segments per corner (smooth enough, cheap)
	# Top edge -> top-right corner
	for i in range(n + 1):
		var a := -PI / 2.0 + (PI / 2.0) * float(i) / float(n)
		pts.append(Vector2(p.x + s.x - r + cos(a) * r, p.y + r + sin(a) * r))
	# Right edge -> bottom-right corner
	for i in range(n + 1):
		var a := 0.0 + (PI / 2.0) * float(i) / float(n)
		pts.append(Vector2(p.x + s.x - r + cos(a) * r, p.y + s.y - r + sin(a) * r))
	# Bottom edge -> bottom-left corner
	for i in range(n + 1):
		var a := PI / 2.0 + (PI / 2.0) * float(i) / float(n)
		pts.append(Vector2(p.x + r + cos(a) * r, p.y + s.y - r + sin(a) * r))
	# Left edge -> top-left corner
	for i in range(n + 1):
		var a := PI + (PI / 2.0) * float(i) / float(n)
		pts.append(Vector2(p.x + r + cos(a) * r, p.y + r + sin(a) * r))
	draw_colored_polygon(pts, color)
