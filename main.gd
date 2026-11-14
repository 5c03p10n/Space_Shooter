extends Node2D

const SCREEN := Vector2(800, 600)
const CX := 400.0
const SHIP_SPEED := 360.0
const BULLET_SPEED := 650.0
const MAX_UPGRADE := 5
const BOSS_RADIUS := 52.0
const PITY := 14

enum State { TITLE, PLAYING, PAUSED, GAME_OVER }

var ship_names := ["SCOUT", "STRIKER", "TWIN HAWK", "ROCK BREAKER", "NOVA WING", "OMEGA PHOENIX"]
var ship_colors := [
	Color(0.3, 0.85, 1.0), Color(0.35, 1.0, 0.55), Color(1.0, 0.9, 0.3),
	Color(1.0, 0.55, 0.2), Color(1.0, 0.35, 0.85), Color(1.0, 0.95, 0.55)
]
var boss_names := ["WARDEN", "DEVOURER", "OVERLORD", "HARBINGER", "VOID TYRANT"]
var boss_colors := [
	Color(1.0, 0.3, 0.3), Color(0.7, 0.35, 1.0), Color(0.3, 1.0, 0.5),
	Color(1.0, 0.6, 0.2), Color(0.3, 0.8, 1.0)
]

var stage_names := ["DEEP SPACE", "EMERALD DRIFT", "VIOLET VOID", "EMBER BELT", "CRIMSON RIFT", "GOLDEN NOVA"]
var bg_base := [
	Color(0.010, 0.020, 0.090), Color(0.000, 0.070, 0.070), Color(0.060, 0.015, 0.110),
	Color(0.100, 0.040, 0.010), Color(0.110, 0.010, 0.070), Color(0.090, 0.070, 0.020)
]
var bg_neb := [
	[Color(0.15, 0.25, 0.80), Color(0.20, 0.10, 0.60), Color(0.10, 0.40, 0.70)],
	[Color(0.10, 0.70, 0.50), Color(0.10, 0.50, 0.40), Color(0.20, 0.80, 0.60)],
	[Color(0.60, 0.20, 0.90), Color(0.40, 0.15, 0.70), Color(0.80, 0.30, 0.80)],
	[Color(0.95, 0.50, 0.15), Color(0.80, 0.30, 0.10), Color(1.00, 0.65, 0.20)],
	[Color(0.95, 0.20, 0.55), Color(0.70, 0.10, 0.40), Color(1.00, 0.35, 0.70)],
	[Color(1.00, 0.85, 0.40), Color(0.90, 0.60, 0.20), Color(1.00, 0.95, 0.70)],
]

var state: int = State.TITLE
var time := 0.0
var state_timer := 0.0
var shake := 0.0
var hitstop := 0.0
var flash := 0.0
var flash_color := Color.WHITE
var muted := false

var cur_bg := Color(0.01, 0.02, 0.09)
var cur_neb: Array[Color] = [Color(0.15, 0.25, 0.8), Color(0.2, 0.1, 0.6), Color(0.1, 0.4, 0.7)]

var ship_pos := Vector2.ZERO
var upgrade := 0
var lives := 3
var score := 0
var best := 0
var new_record := false
var kills := 0
var kills_since_drop := 0
var combo := 0
var combo_timer := 0.0
var assist := 0.0
var invuln := 0.0
var fire_timer := 0.0

var bullets: Array[Dictionary] = []
var enemy_bullets: Array[Dictionary] = []
var aliens: Array[Dictionary] = []
var asteroids: Array[Dictionary] = []
var pickups: Array[Dictionary] = []
var particles: Array[Dictionary] = []
var floaters: Array[Dictionary] = []
var stars: Array[Dictionary] = []
var boss: Dictionary = {}

var boss_count := 0
var boss_prev_score := 0
var next_boss_score := 350
var alien_timer := 0.0
var asteroid_timer := 0.0

var banner_title := ""
var banner_sub := ""
var banner_timer := 0.0
var banner_total := 1.0
var banner_color := Color.WHITE
var banner_alert := false

var sfx := {}
var players: Array[AudioStreamPlayer] = []
var player_idx := 0


func _ready() -> void:
	randomize()
	for i in 90:
		stars.append({
			"pos": Vector2(randf() * SCREEN.x, randf() * SCREEN.y),
			"speed": randf_range(20.0, 140.0),
			"size": randf_range(0.6, 1.8),
		})
	cur_bg = bg_base[0]
	var tn: Array = bg_neb[0]
	for i in 3:
		cur_neb[i] = tn[i]
	setup_audio()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == State.PLAYING:
		state = State.PAUSED


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_P, KEY_ESCAPE:
			if state == State.PLAYING:
				state = State.PAUSED
			elif state == State.PAUSED:
				state = State.PLAYING
				invuln = maxf(invuln, 0.6)
		KEY_M:
			muted = not muted
			AudioServer.set_bus_mute(0, muted)
		KEY_R:
			if state == State.PAUSED:
				start_game()
		KEY_Q:
			if state == State.PAUSED:
				quit_to_title()


func make_sfx(f0: float, f1: float, dur: float, noise: float, vol: float, square: bool) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(n)
		var f := lerpf(f0, f1, t)
		phase += TAU * f / float(rate)
		var s := sin(phase)
		if square:
			s = 1.0 if s > 0.0 else -1.0
		var nz := randf() * 2.0 - 1.0
		var env := (1.0 - t) * (1.0 - t)
		var v := (s * (1.0 - noise) + nz * noise) * vol * env
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


func setup_audio() -> void:
	for i in 10:
		var pl := AudioStreamPlayer.new()
		add_child(pl)
		players.append(pl)
	sfx["shoot"] = make_sfx(900.0, 300.0, 0.09, 0.0, 0.30, true)
	sfx["pop"] = make_sfx(520.0, 120.0, 0.16, 0.5, 0.6, false)
	sfx["rock"] = make_sfx(250.0, 80.0, 0.22, 0.9, 0.7, false)
	sfx["boom"] = make_sfx(160.0, 40.0, 0.5, 0.8, 0.8, false)
	sfx["hit"] = make_sfx(220.0, 60.0, 0.35, 0.6, 0.8, false)
	sfx["pickup"] = make_sfx(400.0, 1200.0, 0.25, 0.0, 0.5, false)
	sfx["upgrade"] = make_sfx(300.0, 1600.0, 0.5, 0.0, 0.55, false)
	sfx["warn"] = make_sfx(500.0, 900.0, 0.7, 0.0, 0.35, true)
	sfx["graze"] = make_sfx(1500.0, 2200.0, 0.06, 0.0, 0.3, false)


func play_sfx(sfx_name: String, db: float = 0.0, pitch: float = 1.0) -> void:
	if not sfx.has(sfx_name) or players.is_empty():
		return
	var p := players[player_idx]
	player_idx = (player_idx + 1) % players.size()
	p.stream = sfx[sfx_name]
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


func clear_world() -> void:
	bullets.clear()
	enemy_bullets.clear()
	aliens.clear()
	asteroids.clear()
	pickups.clear()
	particles.clear()
	floaters.clear()
	boss = {}


func start_game() -> void:
	state = State.PLAYING
	ship_pos = Vector2(CX, SCREEN.y - 80.0)
	upgrade = 0
	lives = 3
	score = 0
	kills = 0
	kills_since_drop = 0
	combo = 0
	combo_timer = 0.0
	assist = 0.0
	invuln = 1.5
	fire_timer = 0.0
	hitstop = 0.0
	flash = 0.0
	new_record = false
	clear_world()
	boss_count = 0
	boss_prev_score = 0
	next_boss_score = 350
	alien_timer = 1.2
	asteroid_timer = 2.0
	play_sfx("pickup", -6.0, 1.2)
	show_banner("GET READY", "SECTOR: " + String(stage_names[0]), Color(0.4, 0.9, 1.0), 2.0)


func quit_to_title() -> void:
	state = State.TITLE
	clear_world()
	upgrade = 0
	hitstop = 0.0
	flash = 0.0
	banner_timer = 0.0


func show_banner(title: String, sub: String, col: Color, dur: float, alert: bool = false) -> void:
	banner_title = title
	banner_sub = sub
	banner_color = col
	banner_timer = dur
	banner_total = dur
	banner_alert = alert


func _process(delta: float) -> void:
	time += delta
	if state == State.PAUSED:
		position = Vector2.ZERO
		queue_redraw()
		return

	update_stars(delta)
	update_particles(delta)
	update_floaters(delta)
	update_palette(delta)
	banner_timer = maxf(0.0, banner_timer - delta)
	flash = maxf(0.0, flash - delta * 2.5)
	shake = maxf(0.0, shake - 40.0 * delta)
	if shake > 0.0:
		position = Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
	else:
		position = Vector2.ZERO

	match state:
		State.TITLE:
			if Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_ENTER):
				start_game()
		State.PLAYING:
			if hitstop > 0.0:
				hitstop -= delta
			else:
				update_game(delta)
		State.GAME_OVER:
			state_timer -= delta
			if state_timer <= 0.0 and (Input.is_key_pressed(KEY_R) or Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_SPACE)):
				start_game()
	queue_redraw()


func update_game(delta: float) -> void:
	handle_input(delta)
	spawn_things(delta)
	update_bullets(delta)
	update_aliens(delta)
	update_boss(delta)
	update_enemy_bullets(delta)
	update_asteroids(delta)
	update_pickups(delta)
	invuln = maxf(0.0, invuln - delta)
	assist = maxf(0.0, assist - delta)
	if combo > 0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			combo = 0


func update_palette(delta: float) -> void:
	var idx := upgrade
	if state == State.TITLE:
		idx = int(time * 0.7) % 6
	var tb: Color = bg_base[idx]
	var tn: Array = bg_neb[idx]
	var boss_on := not boss.is_empty()
	if boss_on:
		tb = tb.lerp(Color(0.14, 0.0, 0.02), 0.5)
	var k := 1.0 - exp(-delta * 1.6)
	cur_bg = cur_bg.lerp(tb, k)
	for i in 3:
		var tc: Color = tn[i]
		if boss_on:
			tc = tc.lerp(Color(1.0, 0.15, 0.1), 0.45)
		cur_neb[i] = cur_neb[i].lerp(tc, k)


func update_stars(delta: float) -> void:
	var mult := 1.0
	if state != State.TITLE:
		mult = 1.0 + upgrade * 0.25
	for s in stars:
		var p: Vector2 = s["pos"]
		var sp: float = s["speed"]
		p.y += sp * mult * delta
		if p.y > SCREEN.y:
			p = Vector2(randf() * SCREEN.x, -2.0)
		s["pos"] = p


func update_particles(delta: float) -> void:
	for i in range(particles.size() - 1, -1, -1):
		var pt := particles[i]
		var p: Vector2 = pt["pos"]
		var v: Vector2 = pt["vel"]
		p += v * delta
		v *= 0.97
		pt["pos"] = p
		pt["vel"] = v
		pt["life"] = float(pt["life"]) - delta
		if float(pt["life"]) <= 0.0:
			particles.remove_at(i)


func update_floaters(delta: float) -> void:
	for i in range(floaters.size() - 1, -1, -1):
		var f := floaters[i]
		var p: Vector2 = f["pos"]
		p.y -= 40.0 * delta
		f["pos"] = p
		f["life"] = float(f["life"]) - delta
		if float(f["life"]) <= 0.0:
			floaters.remove_at(i)


func explode(p: Vector2, col: Color, count: int, speed: float, size: float = 3.0) -> void:
	if particles.size() > 700:
		return
	for i in count:
		var v := Vector2.from_angle(randf() * TAU) * randf_range(speed * 0.3, speed)
		var life := randf_range(0.3, 0.8)
		particles.append({"pos": p, "vel": v, "life": life, "max": life, "color": col, "size": size * randf_range(0.6, 1.3)})


func add_floater(p: Vector2, text: String, col: Color, size: int = 16) -> void:
	if floaters.size() > 24:
		return
	floaters.append({"pos": p, "text": text, "life": 1.0, "color": col, "size": size})


func add_score(base: int, p: Vector2) -> void:
	var m := combo_mult()
	var pts := base * m
	score += pts
	var c := Color(1.0, 0.9, 0.4) if m > 1 else Color.WHITE
	add_floater(p, "+%d" % pts, c)


func combo_mult() -> int:
	return mini(1 + int(combo / 5.0), 5)


func bump_combo(p: Vector2) -> void:
	combo += 1
	combo_timer = 2.2
	if combo % 5 == 0 and combo <= 20:
		add_floater(p + Vector2(0, -26), "COMBO x%d!" % combo_mult(), Color(1.0, 0.6, 0.2), 20)
		play_sfx("pickup", -6.0, 1.0 + combo_mult() * 0.12)


func handle_input(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		dir.y += 1.0
	if dir != Vector2.ZERO:
		ship_pos += dir.normalized() * SHIP_SPEED * delta
	ship_pos.x = clampf(ship_pos.x, 24.0, SCREEN.x - 24.0)
	ship_pos.y = clampf(ship_pos.y, 90.0, SCREEN.y - 24.0)

	fire_timer -= delta
	if Input.is_key_pressed(KEY_SPACE) and fire_timer <= 0.0:
		fire()


func add_bullet(off_x: float, angle_deg: float, dmg: int) -> void:
	var vel := Vector2(0.0, -1.0).rotated(deg_to_rad(angle_deg)) * BULLET_SPEED
	bullets.append({"pos": ship_pos + Vector2(off_x, -18.0), "vel": vel, "dmg": dmg})


func fire() -> void:
	var cd := 0.28
	match upgrade:
		0:
			add_bullet(0.0, 0.0, 1)
			cd = 0.28
		1:
			add_bullet(0.0, 0.0, 1)
			cd = 0.18
		2:
			add_bullet(-9.0, 0.0, 1)
			add_bullet(9.0, 0.0, 1)
			cd = 0.2
		3:
			add_bullet(0.0, 0.0, 1)
			add_bullet(-10.0, -7.0, 1)
			add_bullet(10.0, 7.0, 1)
			cd = 0.2
		4:
			add_bullet(0.0, 0.0, 1)
			add_bullet(-8.0, -8.0, 1)
			add_bullet(8.0, 8.0, 1)
			add_bullet(-14.0, -16.0, 1)
			add_bullet(14.0, 16.0, 1)
			cd = 0.17
		_:
			add_bullet(0.0, 0.0, 2)
			add_bullet(-8.0, -8.0, 1)
			add_bullet(8.0, 8.0, 1)
			add_bullet(-14.0, -16.0, 1)
			add_bullet(14.0, 16.0, 1)
			cd = 0.13
	fire_timer = cd
	play_sfx("shoot", -14.0, randf_range(0.92, 1.1) + upgrade * 0.04)


func upgrade_ship() -> void:
	if upgrade >= MAX_UPGRADE:
		score += 100
		add_floater(ship_pos + Vector2(0, -30), "MAX POWER +100", Color(1.0, 0.9, 0.3))
		explode(ship_pos, Color(1.0, 0.9, 0.3), 14, 200.0)
		play_sfx("pickup", -4.0, 1.3)
		return
	upgrade += 1
	var col: Color = ship_colors[upgrade]
	explode(ship_pos, col, 40, 300.0, 3.5)
	shake = 5.0
	flash = 0.5
	flash_color = col.lightened(0.4)
	play_sfx("upgrade", -2.0)
	add_floater(ship_pos + Vector2(0, -34), "POWER UP!", col, 24)
	var sector := "SECTOR: " + String(stage_names[upgrade])
	if upgrade == 3:
		show_banner("ROCK BREAKER ONLINE", "Your shots now smash asteroids!   " + sector, col, 2.8)
	elif upgrade == MAX_UPGRADE:
		show_banner("MAX UPGRADE", "MK-6  " + String(ship_names[upgrade]) + "   " + sector, col, 2.6)
	else:
		show_banner("UPGRADE %d / %d" % [upgrade, MAX_UPGRADE], "MK-%d  %s   %s" % [upgrade + 1, ship_names[upgrade], sector], col, 2.0)


func hit_ship() -> void:
	lives -= 1
	invuln = 2.0
	shake = 14.0
	hitstop = 0.08
	flash = 0.35
	flash_color = Color(1.0, 0.2, 0.2)
	combo = 0
	assist = 10.0
	var col: Color = ship_colors[upgrade]
	explode(ship_pos, col, 30, 260.0, 4.0)
	play_sfx("hit")
	if lives > 0 and upgrade > 0 and randf() < 0.3 + upgrade * 0.1:
		upgrade -= 1
		add_floater(ship_pos + Vector2(0, -34), "DOWNGRADE", Color(1.0, 0.4, 0.4), 22)
		show_banner("SYSTEMS DAMAGED", "Downgraded to MK-%d  %s" % [upgrade + 1, ship_names[upgrade]], Color(1.0, 0.4, 0.4), 2.0)
	if lives <= 0:
		state = State.GAME_OVER
		state_timer = 1.2
		new_record = score > best and score > 0
		best = maxi(best, score)
		explode(ship_pos, Color.WHITE, 50, 380.0, 4.5)
		shake = 20.0
		play_sfx("boom")


func spawn_things(delta: float) -> void:
	var diff := minf(score / 500.0, 2.0)
	var easy := 1.0
	if assist > 0.0:
		easy = 1.4

	if boss.is_empty():
		if score >= next_boss_score:
			spawn_boss()
		else:
			alien_timer -= delta
			if alien_timer <= 0.0:
				var tough := score > 250 and randf() < 0.25
				aliens.append({
					"pos": Vector2(randf_range(40.0, SCREEN.x - 40.0), -20.0),
					"speed": randf_range(55.0, 90.0) + diff * 30.0,
					"t": 0.0,
					"phase": randf() * TAU,
					"hp": 2 if tough else 1,
					"tough": tough,
				})
				alien_timer = maxf(0.55, 1.8 - diff * 0.4) * easy

	asteroid_timer -= delta
	if asteroid_timer <= 0.0:
		var r := randf_range(14.0, 34.0)
		var pts := PackedVector2Array()
		var n := 9
		for i in n:
			pts.append(Vector2.from_angle(TAU * i / n) * r * randf_range(0.75, 1.1))
		asteroids.append({
			"pos": Vector2(randf_range(r, SCREEN.x - r), -r),
			"vel": Vector2(randf_range(-40.0, 40.0), randf_range(110.0, 180.0) + diff * 40.0),
			"r": r,
			"rot": 0.0,
			"spin": randf_range(-2.0, 2.0),
			"pts": pts,
			"hp": int(r / 12.0) + 1,
			"grazed": false,
		})
		var interval := maxf(0.5, 1.4 - diff * 0.3) * easy
		if not boss.is_empty():
			interval *= 1.6
		asteroid_timer = interval


func spawn_pickup(p: Vector2) -> void:
	pickups.append({"pos": p, "t": 0.0})


func boss_title(lvl: int) -> String:
	var n: String = boss_names[lvl % boss_names.size()]
	if lvl >= boss_names.size():
		n += " MK-%d" % (int(lvl / float(boss_names.size())) + 1)
	return n


func boss_col() -> Color:
	if boss.is_empty():
		return Color.WHITE
	var lvl: int = boss["lvl"]
	var c: Color = boss_colors[lvl % boss_colors.size()]
	return c


func spawn_boss() -> void:
	var lvl := boss_count
	var hp := 90 + lvl * 70
	boss = {
		"pos": Vector2(CX, -90.0), "hp": hp, "max": hp, "t": 0.0,
		"fire_t": 2.8, "lvl": lvl, "enter": true, "flash": 0.0,
	}
	play_sfx("warn", -4.0)
	show_banner("WARNING", "BOSS INCOMING  -  " + boss_title(lvl), Color(1.0, 0.25, 0.25), 3.0, true)


func kill_boss() -> void:
	var p: Vector2 = boss["pos"]
	var lvl: int = boss["lvl"]
	var col := boss_col()
	for i in 4:
		explode(p + Vector2(randf_range(-40.0, 40.0), randf_range(-30.0, 30.0)), col, 30, 320.0, 5.0)
	explode(p, Color.WHITE, 40, 420.0, 4.0)
	shake = 18.0
	hitstop = 0.12
	flash = 0.6
	flash_color = Color(1.0, 0.9, 0.5)
	var pts := 200 + 100 * lvl
	score += pts
	add_floater(p, "BOOM!", Color(1.0, 0.9, 0.3), 34)
	add_floater(p + Vector2(0, 30), "+%d" % pts, Color(1.0, 0.9, 0.3), 20)
	spawn_pickup(p)
	if lives < 3:
		lives += 1
		add_floater(ship_pos + Vector2(0, -30), "+1 LIFE", Color(0.4, 1.0, 0.5), 20)
	play_sfx("boom")
	play_sfx("pickup", -3.0, 1.1)
	enemy_bullets.clear()
	boss = {}
	boss_count += 1
	boss_prev_score = score
	next_boss_score = score + 450 + 100 * boss_count
	show_banner("BOSS DESTROYED", "BONUS  +%d" % pts, Color(1.0, 0.9, 0.3), 2.4)


func update_bullets(delta: float) -> void:
	for i in range(bullets.size() - 1, -1, -1):
		var b := bullets[i]
		var p: Vector2 = b["pos"]
		var v: Vector2 = b["vel"]
		var dmg: int = b["dmg"]
		p += v * delta
		b["pos"] = p
		var used := p.y < -20.0 or p.x < -20.0 or p.x > SCREEN.x + 20.0

		if not used and not boss.is_empty():
			var bp: Vector2 = boss["pos"]
			if p.distance_to(bp) < BOSS_RADIUS:
				boss["hp"] = int(boss["hp"]) - dmg
				boss["flash"] = 0.08
				explode(p, boss_col(), 3, 140.0, 2.0)
				used = true
				if int(boss["hp"]) <= 0:
					kill_boss()

		if not used:
			for j in range(aliens.size() - 1, -1, -1):
				var ap: Vector2 = aliens[j]["pos"]
				if p.distance_to(ap) < 20.0:
					aliens[j]["hp"] = int(aliens[j]["hp"]) - dmg
					used = true
					if int(aliens[j]["hp"]) <= 0:
						kill_alien(j)
					else:
						explode(p, Color(1.0, 0.6, 0.6), 4, 140.0, 2.0)
					break

		if not used:
			for j in range(asteroids.size() - 1, -1, -1):
				var a := asteroids[j]
				var rp: Vector2 = a["pos"]
				var r: float = a["r"]
				if p.distance_to(rp) < r:
					used = true
					if upgrade >= 3:
						a["hp"] = int(a["hp"]) - dmg
						if int(a["hp"]) <= 0:
							break_asteroid(j)
						else:
							explode(p, Color(1.0, 0.7, 0.3), 4, 150.0, 2.5)
					else:
						explode(p, Color(0.7, 0.7, 0.8), 3, 100.0, 2.0)
					break

		if used:
			bullets.remove_at(i)


func kill_alien(j: int) -> void:
	var al := aliens[j]
	var p: Vector2 = al["pos"]
	var tough: bool = al["tough"]
	var col := Color(1.0, 0.4, 0.4) if tough else Color(0.4, 1.0, 0.5)
	explode(p, col, 18, 220.0, 3.5)
	play_sfx("pop", -4.0, randf_range(0.9, 1.15))
	bump_combo(p)
	add_score(15 if tough else 10, p)
	if randf() < 0.25:
		var words := ["ZAP!", "POP!", "BZZT!", "PEW!"]
		add_floater(p + Vector2(0, -18), String(words[randi() % words.size()]), col, 20)
	kills += 1
	kills_since_drop += 1
	if kills_since_drop >= PITY or randf() < 0.05 + kills_since_drop * 0.03:
		spawn_pickup(p)
		kills_since_drop = 0
	aliens.remove_at(j)


func break_asteroid(j: int) -> void:
	var a := asteroids[j]
	var p: Vector2 = a["pos"]
	explode(p, Color(0.85, 0.7, 0.5), 22, 240.0, 3.5)
	play_sfx("rock", -3.0, randf_range(0.9, 1.1))
	shake = maxf(shake, 3.0)
	add_score(5, p)
	add_floater(p + Vector2(0, -18), "CRACK!", Color(1.0, 0.8, 0.5), 20)
	asteroids.remove_at(j)


func update_aliens(delta: float) -> void:
	for i in range(aliens.size() - 1, -1, -1):
		var al := aliens[i]
		var p: Vector2 = al["pos"]
		var t: float = float(al["t"]) + delta
		al["t"] = t
		p.y += float(al["speed"]) * delta
		p.x += sin(t * 2.5 + float(al["phase"])) * 90.0 * delta
		al["pos"] = p
		if p.y > SCREEN.y + 30.0:
			aliens.remove_at(i)
		elif invuln <= 0.0 and p.distance_to(ship_pos) < 28.0:
			explode(p, Color(0.4, 1.0, 0.5), 14, 200.0)
			aliens.remove_at(i)
			hit_ship()


func update_boss(delta: float) -> void:
	if boss.is_empty():
		return
	var bp: Vector2 = boss["pos"]
	var lvl: int = boss["lvl"]
	var t: float = float(boss["t"]) + delta
	boss["t"] = t
	boss["flash"] = maxf(0.0, float(boss["flash"]) - delta)

	if boss["enter"]:
		bp.y += 90.0 * delta
		if bp.y >= 110.0:
			boss["enter"] = false
	else:
		bp.x = CX + sin(t * (0.6 + lvl * 0.07)) * 250.0
		bp.y = 110.0 + sin(t * 1.4) * 18.0
		boss["fire_t"] = float(boss["fire_t"]) - delta
		if float(boss["fire_t"]) <= 0.0:
			boss_fire()
			boss["fire_t"] = maxf(1.0, 2.2 - lvl * 0.15)
	boss["pos"] = bp

	if invuln <= 0.0 and bp.distance_to(ship_pos) < BOSS_RADIUS + 10.0:
		hit_ship()


func boss_fire() -> void:
	var bp: Vector2 = boss["pos"]
	var lvl: int = boss["lvl"]
	var t: float = boss["t"]
	var spd := 190.0 + lvl * 18.0
	var muzzle := bp + Vector2(0, 40)
	var to_ship := (ship_pos - bp).normalized()
	match lvl % 3:
		0:
			for a in [-0.3, 0.0, 0.3]:
				enemy_bullets.append({"pos": muzzle, "vel": to_ship.rotated(a) * spd})
		1:
			for i in 10:
				var ang := TAU * i / 10.0 + t
				enemy_bullets.append({"pos": bp, "vel": Vector2.from_angle(ang) * spd * 0.8})
		_:
			for a in [-0.5, -0.25, 0.0, 0.25, 0.5]:
				enemy_bullets.append({"pos": muzzle, "vel": Vector2(0, 1).rotated(a) * spd})
			enemy_bullets.append({"pos": muzzle, "vel": to_ship * spd * 1.2})


func update_enemy_bullets(delta: float) -> void:
	for i in range(enemy_bullets.size() - 1, -1, -1):
		var b := enemy_bullets[i]
		var p: Vector2 = b["pos"]
		var v: Vector2 = b["vel"]
		p += v * delta
		b["pos"] = p
		if p.x < -20.0 or p.x > SCREEN.x + 20.0 or p.y < -20.0 or p.y > SCREEN.y + 20.0:
			enemy_bullets.remove_at(i)
		elif invuln <= 0.0 and p.distance_to(ship_pos) < 13.0:
			enemy_bullets.remove_at(i)
			hit_ship()


func update_asteroids(delta: float) -> void:
	for i in range(asteroids.size() - 1, -1, -1):
		var a := asteroids[i]
		var p: Vector2 = a["pos"]
		var v: Vector2 = a["vel"]
		var r: float = a["r"]
		p += v * delta
		a["pos"] = p
		a["rot"] = float(a["rot"]) + float(a["spin"]) * delta
		var d := p.distance_to(ship_pos)
		if p.y > SCREEN.y + 50.0 or p.x < -60.0 or p.x > SCREEN.x + 60.0:
			asteroids.remove_at(i)
		elif invuln <= 0.0 and d < r + 12.0:
			explode(p, Color(0.85, 0.7, 0.5), 16, 220.0)
			asteroids.remove_at(i)
			hit_ship()
		elif invuln <= 0.0 and not bool(a["grazed"]) and d < r + 32.0:
			a["grazed"] = true
			score += 2
			if combo > 0:
				combo_timer = maxf(combo_timer, 1.2)
			add_floater(ship_pos + Vector2(0, -26), "GRAZE +2", Color(0.5, 0.95, 1.0), 13)
			play_sfx("graze", -8.0, randf_range(0.95, 1.15))


func update_pickups(delta: float) -> void:
	for i in range(pickups.size() - 1, -1, -1):
		var pk := pickups[i]
		var p: Vector2 = pk["pos"]
		var t: float = float(pk["t"]) + delta
		pk["t"] = t
		p.y += 90.0 * delta
		p.x += sin(t * 3.0) * 30.0 * delta
		pk["pos"] = p
		if p.y > SCREEN.y + 30.0:
			pickups.remove_at(i)
		elif p.distance_to(ship_pos) < 30.0:
			pickups.remove_at(i)
			upgrade_ship()


func label(s: String, pos: Vector2, size: int, col: Color, center: bool = false, outline: int = 4, glow_on: bool = false) -> void:
	var font := ThemeDB.fallback_font
	var al: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT
	var w := -1.0
	var pp := pos
	if center:
		al = HORIZONTAL_ALIGNMENT_CENTER
		w = 800.0
		pp = Vector2(pos.x - 400.0, pos.y)
	if glow_on:
		draw_string_outline(font, pp, s, al, w, size, outline + 10, Color(col.r, col.g, col.b, 0.10 * col.a))
		draw_string_outline(font, pp, s, al, w, size, outline + 5, Color(col.r, col.g, col.b, 0.22 * col.a))
	draw_string_outline(font, pp, s, al, w, size, outline, Color(0, 0, 0, 0.85 * col.a))
	draw_string(font, pp, s, al, w, size, col)


func glow(p: Vector2, r: float, c: Color, strength: float = 0.15) -> void:
	for i in 4:
		draw_circle(p, r * (1.0 + i * 0.6), Color(c.r, c.g, c.b, strength / (i + 1.0)))


func poly(p: Vector2, s: float, pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in pts:
		var vv: Vector2 = v
		out.append(p + vv * s)
	return out


func outline(pts: PackedVector2Array, col: Color, w: float) -> void:
	var o := PackedVector2Array(pts)
	o.append(pts[0])
	draw_polyline(o, col, w)


func _draw() -> void:
	draw_background()

	if state == State.TITLE:
		draw_title()
		return

	draw_asteroids()
	draw_pickups()
	draw_aliens()
	draw_boss()
	draw_enemy_bullets()
	draw_bullets()
	if state == State.PLAYING or state == State.PAUSED:
		draw_player()
	draw_particles()
	draw_floaters()
	draw_hud()
	draw_banner()
	if flash > 0.0:
		draw_rect(Rect2(-30, -30, SCREEN.x + 60, SCREEN.y + 60), Color(flash_color.r, flash_color.g, flash_color.b, flash * 0.5))
	if state == State.PAUSED:
		draw_pause()
	if state == State.GAME_OVER:
		draw_game_over()


func draw_background() -> void:
	draw_rect(Rect2(-30, -30, SCREEN.x + 60, SCREEN.y + 60), cur_bg)
	for i in 3:
		var c := Vector2(150.0 + i * 250.0, 240.0 + sin(time * 0.1 + i) * 90.0)
		var nc := cur_neb[i]
		draw_circle(c, 210.0, Color(nc.r, nc.g, nc.b, 0.05))
		draw_circle(c, 140.0, Color(nc.r, nc.g, nc.b, 0.06))
		draw_circle(c, 70.0, Color(nc.r, nc.g, nc.b, 0.05))
	var tint := cur_neb[0].lightened(0.6)
	var streak := state != State.TITLE and upgrade >= 4
	for s in stars:
		var sz: float = s["size"]
		var sp: Vector2 = s["pos"]
		var spd: float = s["speed"]
		var sc := Color(tint.r, tint.g, tint.b, 0.3 + sz * 0.22)
		if streak:
			draw_line(sp, sp - Vector2(0, spd * 0.07), sc, sz)
		else:
			draw_circle(sp, sz, sc)


func draw_ship(p: Vector2, lvl: int, s: float = 1.0, flame: bool = true) -> void:
	var c: Color = ship_colors[lvl]
	var dark := c.darkened(0.55)
	if flame:
		var fl := 10.0 + randf() * 8.0 + lvl * 2.0
		draw_colored_polygon(poly(p, s, [Vector2(-5, 10), Vector2(5, 10), Vector2(0, 10.0 + fl)]), Color(1.0, 0.55, 0.1, 0.85))
		draw_colored_polygon(poly(p, s, [Vector2(-3, 10), Vector2(3, 10), Vector2(0, 10.0 + fl * 0.6)]), Color(1.0, 1.0, 0.8, 0.95))
	for side in 2:
		var sx := -1.0 if side == 0 else 1.0
		if lvl >= 4:
			var blade := poly(p, s, [Vector2(sx * 16.0, -4), Vector2(sx * 34.0, 20), Vector2(sx * 12.0, 12)])
			draw_colored_polygon(blade, dark)
			outline(blade, c, 1.5)
		if lvl >= 1:
			var wing := poly(p, s, [Vector2(sx * 10.0, 2), Vector2(sx * 25.0, 18), Vector2(sx * 8.0, 14)])
			draw_colored_polygon(wing, dark.lightened(0.15))
			outline(wing, c, 1.5)
		if lvl >= 2:
			draw_rect(Rect2(p + Vector2(sx * 13.0 - 2.0, -8.0) * s, Vector2(4, 16) * s), dark.lightened(0.25))
			draw_circle(p + Vector2(sx * 13.0, -9.0) * s, 2.5 * s, c.lightened(0.6))
	var nose := 20.0 if lvl < 3 else 27.0
	var body := poly(p, s, [Vector2(0, -nose), Vector2(13, 14), Vector2(0, 8), Vector2(-13, 14)])
	draw_colored_polygon(body, c.darkened(0.25))
	outline(body, c.lightened(0.3), 2.0)
	draw_line(p + Vector2(0, -nose + 6.0) * s, p + Vector2(0, 6) * s, c.lightened(0.5), 2.0 * s)
	draw_circle(p + Vector2(0, -3) * s, 4.0 * s, Color(0.85, 0.95, 1.0))
	if lvl >= 5:
		glow(p, 24.0 * s, c, 0.06)
		draw_arc(p, 30.0 * s, time * 2.0, time * 2.0 + TAU * 0.8, 24, c, 2.5 * s)


func draw_player() -> void:
	if invuln > 0.0 and int(invuln * 12.0) % 2 == 0:
		return
	var col: Color = ship_colors[upgrade]
	glow(ship_pos, 18.0, col, 0.08)
	draw_ship(ship_pos, upgrade)
	if invuln > 0.0:
		draw_arc(ship_pos, 30.0, 0.0, TAU, 28, Color(0.5, 0.9, 1.0, 0.5), 2.0)


func draw_bullets() -> void:
	var col: Color = ship_colors[upgrade]
	for b in bullets:
		var p: Vector2 = b["pos"]
		var v: Vector2 = b["vel"]
		var dmg: int = b["dmg"]
		var w := 7.0 if dmg >= 2 else 4.0
		var d := v.normalized() * 9.0
		glow(p, w * 1.1, col, 0.2)
		draw_line(p - d, p + d, col.lightened(0.55), w)


func draw_enemy_bullets() -> void:
	for b in enemy_bullets:
		var p: Vector2 = b["pos"]
		glow(p, 5.0, Color(1.0, 0.3, 0.3), 0.3)
		draw_circle(p, 4.5, Color(1.0, 0.45, 0.35))
		draw_circle(p, 2.2, Color(1.0, 0.95, 0.8))


func draw_aliens() -> void:
	for al in aliens:
		var p: Vector2 = al["pos"]
		var tough: bool = al["tough"]
		var c := Color(1.0, 0.35, 0.35) if tough else Color(0.35, 1.0, 0.45)
		glow(p, 16.0, c, 0.1)
		draw_circle(p + Vector2(0, 2), 16.0, c.darkened(0.35))
		draw_circle(p, 14.0, c)
		draw_circle(p + Vector2(0, -6), 8.0, c.lightened(0.5))
		draw_circle(p + Vector2(-6, -2), 3.8, Color.WHITE)
		draw_circle(p + Vector2(6, -2), 3.8, Color.WHITE)
		draw_circle(p + Vector2(-6, -1), 1.7, Color.BLACK)
		draw_circle(p + Vector2(6, -1), 1.7, Color.BLACK)
		draw_line(p + Vector2(-8, -13), p + Vector2(-13, -22), c, 2.0)
		draw_line(p + Vector2(8, -13), p + Vector2(13, -22), c, 2.0)
		if tough:
			draw_arc(p, 21.0, 0.0, TAU, 20, Color(1, 1, 1, 0.5), 2.0)


func draw_asteroids() -> void:
	for a in asteroids:
		var p: Vector2 = a["pos"]
		var rot: float = a["rot"]
		var pts: PackedVector2Array = a["pts"]
		var rock := Color(0.45, 0.4, 0.35)
		if upgrade >= 3:
			rock = Color(0.5, 0.38, 0.3)
		draw_set_transform(p, rot, Vector2.ONE)
		draw_colored_polygon(pts, rock)
		outline(pts, Color(0.8, 0.72, 0.6), 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func draw_pickups() -> void:
	for pk in pickups:
		var p: Vector2 = pk["pos"]
		var t: float = pk["t"]
		var col := Color.from_hsv(fmod(t * 0.8, 1.0), 0.6, 1.0)
		var r := 13.0 + sin(t * 6.0) * 1.5
		glow(p, 14.0, col, 0.25)
		var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)])
		draw_colored_polygon(pts, Color(0.05, 0.05, 0.14))
		outline(pts, col, 2.5)
		draw_line(p + Vector2(0, 5), p + Vector2(0, -5), col, 2.5)
		draw_line(p + Vector2(-4, -1), p + Vector2(0, -5), col, 2.5)
		draw_line(p + Vector2(4, -1), p + Vector2(0, -5), col, 2.5)


func draw_boss() -> void:
	if boss.is_empty():
		return
	var p: Vector2 = boss["pos"]
	var col := boss_col()
	var fl: float = boss["flash"]
	var ratio := float(boss["hp"]) / float(boss["max"])
	var body := col.darkened(0.6)
	if fl > 0.0:
		body = Color.WHITE
	elif ratio < 0.3 and int(time * 8.0) % 2 == 0:
		body = Color(0.6, 0.1, 0.1)

	glow(p, 50.0, col, 0.1)
	for side in 2:
		var sx := -1.0 if side == 0 else 1.0
		var wing := poly(p, 1.0, [Vector2(sx * 36.0, -14), Vector2(sx * 88.0, 6), Vector2(sx * 74.0, 44), Vector2(sx * 36.0, 26)])
		draw_colored_polygon(wing, body)
		outline(wing, col, 2.5)
		draw_rect(Rect2(p + Vector2(sx * 28.0 - 5.0, 30.0), Vector2(10, 22)), body)
		glow(p + Vector2(sx * 28.0, 54.0), 6.0, col, 0.3)
		var spike := poly(p, 1.0, [Vector2(sx * 16.0, -44), Vector2(sx * 24.0, -66), Vector2(sx * 30.0, -38)])
		draw_colored_polygon(spike, body)
		outline(spike, col, 2.0)

	var hexa := PackedVector2Array()
	for i in 8:
		var a := TAU * i / 8.0 + PI / 8.0
		var r := 48.0 if i % 2 == 0 else 40.0
		hexa.append(p + Vector2.from_angle(a) * r)
	draw_colored_polygon(hexa, body)
	outline(hexa, col, 3.0)

	var dir := (ship_pos - p).normalized()
	draw_circle(p, 21.0, Color(0.05, 0.0, 0.05))
	draw_circle(p, 18.0, col)
	glow(p + dir * 5.0, 9.0, Color.WHITE, 0.18)
	draw_circle(p + dir * 6.0, 8.0, Color.WHITE)
	draw_circle(p + dir * 8.0, 4.0, Color.BLACK)


func draw_particles() -> void:
	for pt in particles:
		var f: float = float(pt["life"]) / float(pt["max"])
		var c: Color = pt["color"]
		var p: Vector2 = pt["pos"]
		draw_circle(p, maxf(0.5, float(pt["size"]) * f), Color(c.r, c.g, c.b, f))


func draw_floaters() -> void:
	for f in floaters:
		var p: Vector2 = f["pos"]
		var c: Color = f["color"]
		var sz: int = f["size"]
		var a := clampf(float(f["life"]), 0.0, 1.0)
		label(String(f["text"]), p, sz, Color(c.r, c.g, c.b, a), true, 3)


func draw_hud() -> void:
	draw_rect(Rect2(-30, -30, SCREEN.x + 60, 82), Color(0.02, 0.03, 0.10, 0.72))
	draw_rect(Rect2(-30, 52, SCREEN.x + 60, 2), Color(0.2, 0.9, 1.0, 0.9))
	draw_rect(Rect2(-30, 54, SCREEN.x + 60, 4), Color(0.2, 0.9, 1.0, 0.12))

	label("SCORE", Vector2(16, 18), 12, Color(0.4, 0.9, 1.0), false, 2)
	label("%06d" % score, Vector2(16, 46), 28, Color.WHITE, false, 4, true)

	var pod_col := Color(1.0, 0.85, 0.3)
	var pf := clampf(float(kills_since_drop) / float(PITY), 0.0, 1.0)
	label("POD", Vector2(140, 22), 11, pod_col, false, 2)
	draw_rect(Rect2(139, 29, 94, 10), Color(1, 1, 1, 0.12))
	draw_rect(Rect2(140, 30, 92.0 * pf, 8), pod_col)
	if pf > 0.75 and int(time * 6.0) % 2 == 0:
		draw_rect(Rect2(138, 28, 96, 12), Color(pod_col.r, pod_col.g, pod_col.b, 0.25))

	var col: Color = ship_colors[upgrade]
	label("MK-%d   %s" % [upgrade + 1, ship_names[upgrade]], Vector2(CX, 24), 16, col, true, 3)
	var pw := 30.0
	var gap := 6.0
	var x0 := (SCREEN.x - (MAX_UPGRADE * pw + (MAX_UPGRADE - 1) * gap)) / 2.0
	for i in MAX_UPGRADE:
		var r := Rect2(x0 + i * (pw + gap), 33.0, pw, 10.0)
		if i < upgrade:
			draw_rect(Rect2(r.position - Vector2(2, 2), r.size + Vector2(4, 4)), Color(col.r, col.g, col.b, 0.25))
			draw_rect(r, col)
		else:
			draw_rect(r, Color(1, 1, 1, 0.12))

	label("LIVES", Vector2(SCREEN.x - 150, 18), 12, Color(0.4, 0.9, 1.0), false, 2)
	for i in 3:
		var lp := Vector2(SCREEN.x - 135.0 + i * 40.0, 36.0)
		if i < lives:
			draw_ship(lp, upgrade, 0.7, false)
		else:
			draw_arc(lp, 8.0, 0.0, TAU, 16, Color(1, 1, 1, 0.2), 2.0)

	if combo >= 2:
		var m := combo_mult()
		var cc := Color(1.0, 0.85 - m * 0.1, 0.3)
		label("x%d" % m, Vector2(SCREEN.x - 150, 98), 26, cc, false, 4, true)
		label("%d HIT CHAIN" % combo, Vector2(SCREEN.x - 112, 90), 12, Color(1, 1, 1, 0.8), false, 2)
		draw_rect(Rect2(SCREEN.x - 150, 104, 110, 4), Color(1, 1, 1, 0.15))
		draw_rect(Rect2(SCREEN.x - 150, 104, 110.0 * clampf(combo_timer / 2.2, 0.0, 1.0), 4), cc)

	if not boss.is_empty():
		var bc := boss_col()
		var lvl: int = boss["lvl"]
		var w := 460.0
		var x := (SCREEN.x - w) / 2.0
		var ratio := clampf(float(boss["hp"]) / float(boss["max"]), 0.0, 1.0)
		label("BOSS  -  " + boss_title(lvl), Vector2(CX, 72), 14, bc, true, 3, true)
		draw_rect(Rect2(x - 3, 77, w + 6, 18), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(x, 80, w * ratio, 12), bc)
		draw_rect(Rect2(x, 80, w * ratio, 4), Color(1, 1, 1, 0.35))
		draw_rect(Rect2(x - 2, 78, w + 4, 16), bc, false, 2.0)
	else:
		var span := float(maxi(1, next_boss_score - boss_prev_score))
		var prog := clampf(float(score - boss_prev_score) / span, 0.0, 1.0)
		label("NEXT BOSS", Vector2(16, SCREEN.y - 22), 11, Color(1.0, 0.45, 0.45), false, 2)
		draw_rect(Rect2(15, SCREEN.y - 17, 144, 8), Color(1, 1, 1, 0.12))
		draw_rect(Rect2(16, SCREEN.y - 16, 142.0 * prog, 6), Color(1.0, 0.35, 0.35))

	label("SECTOR  " + String(stage_names[upgrade]), Vector2(SCREEN.x - 210, SCREEN.y - 14), 11, Color(col.r, col.g, col.b, 0.8), false, 2)
	var hint := "P  PAUSE      M  SOUND OFF" if not muted else "P  PAUSE      M  SOUND ON"
	label(hint, Vector2(CX, SCREEN.y - 14), 11, Color(0.6, 0.75, 0.9, 0.7), true, 2)


func draw_banner() -> void:
	if banner_timer <= 0.0:
		return
	var c := banner_color
	var a := clampf(banner_timer / 0.5, 0.0, 1.0)
	var intro := clampf((banner_total - banner_timer) / 0.25, 0.0, 1.0)
	if banner_alert:
		var f := 0.5 + 0.5 * sin(time * 14.0)
		draw_rect(Rect2(-30, -30, SCREEN.x + 60, SCREEN.y + 60), Color(1, 0, 0, 0.08 * f * a))
		draw_rect(Rect2(0, 0, SCREEN.x, 8), Color(1, 0.1, 0.1, 0.6 * f * a))
		draw_rect(Rect2(0, SCREEN.y - 8, SCREEN.x, 8), Color(1, 0.1, 0.1, 0.6 * f * a))
	var y := SCREEN.y * 0.38
	draw_rect(Rect2(-30, y - 50, SCREEN.x + 60, 100), Color(0, 0, 0, 0.55 * a * intro))
	draw_rect(Rect2(-30, y - 50, SCREEN.x + 60, 3), Color(c.r, c.g, c.b, a))
	draw_rect(Rect2(-30, y + 47, SCREEN.x + 60, 3), Color(c.r, c.g, c.b, a))
	var size := int(36.0 + (1.0 - intro) * 24.0 + sin(time * 10.0) * 2.0)
	label(banner_title, Vector2(CX, y + 8), size, Color(c.r, c.g, c.b, a), true, 6, true)
	label(banner_sub, Vector2(CX, y + 36), 15, Color(1, 1, 1, a), true, 3)


func draw_pause() -> void:
	draw_rect(Rect2(-30, -30, SCREEN.x + 60, SCREEN.y + 60), Color(0.0, 0.02, 0.08, 0.72))
	label("PAUSED", Vector2(CX, 230), 64, Color(0.4, 0.9, 1.0), true, 8, true)
	var sound_state := "OFF" if muted else "ON"
	var items := [
		"P / ESC        RESUME",
		"R        RESTART",
		"Q        QUIT TO TITLE",
		"M        SOUND: " + sound_state,
	]
	for i in items.size():
		label(String(items[i]), Vector2(CX, 305.0 + i * 36.0), 20, Color.WHITE, true, 4)
	label("ARROWS / WASD  MOVE        SPACE  FIRE", Vector2(CX, 500), 14, Color(0.6, 0.75, 0.9), true, 3)


func draw_title() -> void:
	var tc := Color.from_hsv(fmod(time * 0.15, 1.0), 0.55, 1.0)
	label("STAR BREAKER", Vector2(CX, 190.0 + sin(time * 2.0) * 4.0), 66, tc, true, 8, true)
	label("S P A C E   S H O O T E R", Vector2(CX, 228), 16, Color(0.7, 0.85, 1.0), true, 3)

	var lvl := int(time * 0.7) % 6
	var sc: Color = ship_colors[lvl]
	var sp := Vector2(CX, 330.0 + sin(time * 2.0) * 8.0)
	glow(sp, 40.0, sc, 0.08)
	draw_ship(sp, lvl, 2.0, true)
	label("MK-%d   %s" % [lvl + 1, ship_names[lvl]], Vector2(CX, 408), 18, sc, true, 3)

	if int(time * 2.0) % 2 == 0:
		label("PRESS SPACE TO START", Vector2(CX, 470), 26, Color.WHITE, true, 5, true)
	label("ARROWS / WASD  MOVE      SPACE  FIRE      P  PAUSE      M  SOUND", Vector2(CX, 520), 14, Color(0.6, 0.75, 0.9), true, 3)
	label("Grab upgrade pods. From MK-4 your shots smash asteroids. Beat the bosses!", Vector2(CX, 545), 13, Color(0.6, 0.75, 0.9), true, 3)
	if best > 0:
		label("BEST  %06d" % best, Vector2(CX, 580), 16, Color(1.0, 0.9, 0.3), true, 3)


func draw_game_over() -> void:
	draw_rect(Rect2(-30, -30, SCREEN.x + 60, SCREEN.y + 60), Color(0, 0, 0, 0.6))
	label("GAME OVER", Vector2(CX, 240), 64, Color(1.0, 0.25, 0.25), true, 8, true)
	label("SCORE  %06d" % score, Vector2(CX, 310), 30, Color.WHITE, true, 5)
	if new_record:
		var pulse := 0.75 + 0.25 * sin(time * 8.0)
		label("NEW PERSONAL BEST!", Vector2(CX, 350), 24, Color(1.0, 0.9, 0.3, pulse), true, 4, true)
	else:
		label("BEST  %06d   -   only %d to beat it!" % [best, best - score + 1], Vector2(CX, 350), 16, Color(1.0, 0.9, 0.3), true, 3)
	var sc: Color = ship_colors[upgrade]
	label("REACHED  MK-%d %s      BOSSES DEFEATED  %d" % [upgrade + 1, ship_names[upgrade], boss_count], Vector2(CX, 385), 15, sc, true, 3)
	if state_timer <= 0.0 and int(time * 2.0) % 2 == 0:
		label("PRESS R TO PLAY AGAIN", Vector2(CX, 460), 24, Color.WHITE, true, 5, true)
