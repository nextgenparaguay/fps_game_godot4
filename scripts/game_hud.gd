class_name GameHud
extends CanvasLayer
## In-game HUD, drawn directly on one full-screen Control so it needs no scene.
##
##   bottom-left   health bar: current / max, colour-coded, with a "damage trail"
##   bottom-right  magazine / reserve ammo, reload progress, weapon-slot list
##   centre        contextual hint (RELOADING / LOW AMMO / C4 controls)
##   lower-centre  pickup toasts
##   fullscreen    low-health vignette, heal flash and the sniper scope overlay
##
## The layout scales from the viewport size; every number you might want to tweak
## is a constant at the top.

const MARGIN := 26.0
const HEALTH_BAR_SIZE := Vector2(320.0, 24.0)
const TOAST_TIME := 2.6
const LOW_HEALTH := 0.25
const MID_HEALTH := 0.5

const C_GREEN := Color(0.36, 0.88, 0.46)
const C_AMBER := Color(1.0, 0.76, 0.25)
const C_RED := Color(1.0, 0.27, 0.22)
const C_TEXT := Color(1.0, 1.0, 1.0, 0.95)
const C_DIM := Color(1.0, 1.0, 1.0, 0.55)

const SCOPE_SHADER := """
shader_type canvas_item;
uniform float aspect = 1.78;
uniform float radius = 0.42;
uniform float strength : hint_range(0.0, 1.0) = 1.0;
void fragment() {
	vec2 p = (UV - vec2(0.5)) * vec2(aspect, 1.0);
	float d = length(p);
	float edge = smoothstep(radius - 0.004, radius + 0.004, d);
	float vig = smoothstep(radius * 0.72, radius, d) * 0.4;
	COLOR = vec4(0.0, 0.0, 0.0, max(edge, vig) * strength);
}
"""

var player: Player
var weapon: Weapon

var _canvas: Control
var _scope: ColorRect
var _scope_mat: ShaderMaterial
var _font: Font

var _hp_frac := 1.0                 # smoothed
var _hp_trail := 1.0                # the pale "recent damage" segment
var _trail_delay := 0.0
var _heal_flash := 0.0
var _pulse := 0.0
var _toasts: Array[Dictionary] = []


func setup(p: Player) -> void:
	player = p
	weapon = p.weapon
	layer = 1
	_font = ThemeDB.fallback_font

	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_hud)
	add_child(_canvas)

	_scope = ColorRect.new()
	_scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scope.set_anchors_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = SCOPE_SHADER
	_scope_mat = ShaderMaterial.new()
	_scope_mat.shader = shader
	_scope.material = _scope_mat
	_scope.visible = false
	add_child(_scope)
	move_child(_scope, 0)           # scope sits under the rest of the HUD

	_hp_frac = player.health / maxf(player.max_health, 1.0)
	_hp_trail = _hp_frac
	player.health_changed.connect(_on_health_changed)
	weapon.message.connect(toast)


func toast(text: String, color := Color(1.0, 1.0, 1.0)) -> void:
	_toasts.push_front({"text": text, "color": color, "t": TOAST_TIME})
	if _toasts.size() > 5:
		_toasts.resize(5)


func _on_health_changed(new_health: float) -> void:
	var f := clampf(new_health / maxf(player.max_health, 1.0), 0.0, 1.0)
	if f > _hp_frac + 0.001:
		_heal_flash = 1.0
	elif f < _hp_frac - 0.001:
		_trail_delay = 0.45


func _process(delta: float) -> void:
	if player == null:
		return
	var target := clampf(player.health / maxf(player.max_health, 1.0), 0.0, 1.0)
	_hp_frac = lerpf(_hp_frac, target, 1.0 - exp(-14.0 * delta))
	# The pale trail lingers briefly after a hit, then drains down to the real value.
	if _hp_trail < _hp_frac:
		_hp_trail = _hp_frac
	else:
		_trail_delay = maxf(_trail_delay - delta, 0.0)
		if _trail_delay <= 0.0:
			_hp_trail = move_toward(_hp_trail, _hp_frac, 0.35 * delta)
	_heal_flash = maxf(_heal_flash - delta * 2.5, 0.0)
	_pulse += delta * lerpf(2.0, 7.0, 1.0 - clampf(target / LOW_HEALTH, 0.0, 1.0))

	for t in _toasts:
		t["t"] = float(t["t"]) - delta
	_toasts = _toasts.filter(func(t: Dictionary) -> bool: return float(t["t"]) > 0.0)

	_update_scope()
	_canvas.queue_redraw()


func _update_scope() -> void:
	var show_scope := bool(weapon.current_def.get("scope", false)) and weapon.ads_amount > 0.55
	_scope.visible = show_scope
	if show_scope:
		var vs := get_viewport().get_visible_rect().size
		_scope_mat.set_shader_parameter("aspect", vs.x / maxf(vs.y, 1.0))
		_scope_mat.set_shader_parameter("strength",
				smoothstep(0.55, 0.95, weapon.ads_amount))


# ----------------------------------------------------------------------------
# Drawing
# ----------------------------------------------------------------------------

func _draw_hud() -> void:
	if player == null:
		return
	var vs := _canvas.size
	_draw_vignettes(vs)
	_draw_health(vs)
	_draw_ammo(vs)
	_draw_slots(vs)
	_draw_hint(vs)
	_draw_toasts(vs)
	if weapon.is_scoped():
		_draw_scope_reticle(vs)


func _draw_health(vs: Vector2) -> void:
	var pos := Vector2(MARGIN, vs.y - 80.0)
	var frac := clampf(_hp_frac, 0.0, 1.0)
	var col := _health_color(frac)
	if frac < LOW_HEALTH:
		col.a = 0.65 + 0.35 * sin(_pulse * TAU * 0.5)

	_text(pos + Vector2(0, -8), "HEALTH", 14, C_DIM)

	var back := Rect2(pos, HEALTH_BAR_SIZE)
	_canvas.draw_rect(back.grow(3.0), Color(0, 0, 0, 0.55))
	_canvas.draw_rect(back, Color(0.12, 0.13, 0.15, 0.9))
	# recent-damage trail, then the live bar
	_canvas.draw_rect(Rect2(pos, Vector2(HEALTH_BAR_SIZE.x * clampf(_hp_trail, 0.0, 1.0), HEALTH_BAR_SIZE.y)),
			Color(1.0, 1.0, 1.0, 0.45))
	_canvas.draw_rect(Rect2(pos, Vector2(HEALTH_BAR_SIZE.x * frac, HEALTH_BAR_SIZE.y)), col)
	# segment ticks every 25%
	for i in range(1, 4):
		var x := pos.x + HEALTH_BAR_SIZE.x * i / 4.0
		_canvas.draw_line(Vector2(x, pos.y), Vector2(x, pos.y + HEALTH_BAR_SIZE.y), Color(0, 0, 0, 0.45), 1.5)
	if _heal_flash > 0.0:
		_canvas.draw_rect(back, Color(0.6, 1.0, 0.7, 0.5 * _heal_flash))

	var txt := "%d / %d" % [int(ceil(player.health)), int(player.max_health)]
	_text(pos + Vector2(0, HEALTH_BAR_SIZE.y - 5.0), txt, 17, C_TEXT,
			HORIZONTAL_ALIGNMENT_CENTER, HEALTH_BAR_SIZE.x)


func _draw_ammo(vs: Vector2) -> void:
	var right := vs.x - MARGIN
	var kind := weapon.current_kind()
	var mag := weapon.ammo_in_mag()
	var low := false
	var big := str(mag)
	var small := ""
	if kind == "gun":
		small = " / %d" % weapon.ammo_reserve()
		low = mag <= maxi(int(int(weapon.current_def["mag"]) * 0.25), 1)
	elif kind == "grenade":
		big = "x%d" % mag
	elif kind == "c4":
		big = "x%d" % mag
		small = "  (%d placed)" % weapon.placed_c4_count()

	var big_col := C_TEXT
	if kind == "gun" and (low or mag == 0):
		big_col = C_RED if (mag == 0 or _blink()) else C_AMBER
	var small_w := _width(small, 26)
	var big_w := _width(big, 54)
	_text(Vector2(right - small_w - big_w, vs.y - 54.0), big, 54, big_col)
	_text(Vector2(right - small_w, vs.y - 54.0), small, 26, C_DIM)
	_text(Vector2(right - 300.0, vs.y - 112.0), weapon.current_name().to_upper(), 17, C_DIM,
			HORIZONTAL_ALIGNMENT_RIGHT, 300.0)

	# Reload progress bar
	if weapon.is_reloading():
		var w := 240.0
		var r := Rect2(Vector2(right - w, vs.y - 38.0), Vector2(w, 7.0))
		_canvas.draw_rect(r.grow(2.0), Color(0, 0, 0, 0.55))
		_canvas.draw_rect(r, Color(0.15, 0.16, 0.18, 0.9))
		_canvas.draw_rect(Rect2(r.position, Vector2(w * weapon.reload_progress(), r.size.y)), C_AMBER)


func _draw_slots(vs: Vector2) -> void:
	var entries := weapon.slot_entries()
	var right := vs.x - MARGIN
	var y := vs.y - 150.0 - float(entries.size()) * 26.0
	for e in entries:
		var selected := bool(e["selected"])
		var col := C_TEXT if selected else C_DIM
		var label := "%s  %s %s" % [e["key"], str(e["name"]).to_upper(), e["count"]]
		var w := _width(label, 17)
		if selected:
			var box := Rect2(Vector2(right - w - 10.0, y - 18.0), Vector2(w + 20.0, 24.0))
			_canvas.draw_rect(box, Color(1.0, 1.0, 1.0, 0.12))
			_canvas.draw_rect(Rect2(box.position, Vector2(3.0, box.size.y)), C_AMBER)
		_text(Vector2(right - w, y), label, 17, col)
		y += 26.0


func _draw_hint(vs: Vector2) -> void:
	var hint := weapon.hint_text()
	if hint == "":
		return
	var col := C_AMBER
	if hint.begins_with("NO AMMO") or hint.begins_with("PRESS R"):
		col = C_RED if _blink() else C_AMBER
	elif weapon.current_kind() != "gun":
		col = C_DIM
	_text(Vector2(0.0, vs.y * 0.64), hint, 18, col, HORIZONTAL_ALIGNMENT_CENTER, vs.x)


func _draw_toasts(vs: Vector2) -> void:
	var y := vs.y * 0.74
	for t in _toasts:
		var a := clampf(float(t["t"]) / 0.5, 0.0, 1.0)
		var c: Color = t["color"]
		c.a = a
		_text(Vector2(0.0, y), str(t["text"]), 20, c, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		y -= 28.0


func _draw_vignettes(vs: Vector2) -> void:
	var frac := player.health / maxf(player.max_health, 1.0)
	if frac < LOW_HEALTH and not player.is_dead():
		var a := (0.18 + 0.12 * sin(_pulse * TAU * 0.5)) * (1.0 - frac / LOW_HEALTH)
		var t := 46.0
		var c := Color(0.9, 0.0, 0.0, a)
		_canvas.draw_rect(Rect2(0, 0, vs.x, t), c)
		_canvas.draw_rect(Rect2(0, vs.y - t, vs.x, t), c)
		_canvas.draw_rect(Rect2(0, 0, t, vs.y), c)
		_canvas.draw_rect(Rect2(vs.x - t, 0, t, vs.y), c)
	if _heal_flash > 0.0:
		_canvas.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.3, 1.0, 0.5, 0.10 * _heal_flash))


func _draw_scope_reticle(vs: Vector2) -> void:
	var c := vs * 0.5
	var r := vs.y * 0.42
	var col := Color(0, 0, 0, 0.9)
	_canvas.draw_line(c + Vector2(-r, 0), c + Vector2(-8, 0), col, 1.5)
	_canvas.draw_line(c + Vector2(8, 0), c + Vector2(r, 0), col, 1.5)
	_canvas.draw_line(c + Vector2(0, -r), c + Vector2(0, -8), col, 1.5)
	_canvas.draw_line(c + Vector2(0, 8), c + Vector2(0, r), col, 1.5)
	_canvas.draw_circle(c, 2.0, Color(1.0, 0.2, 0.15, 0.9))
	for i in range(1, 5):                                 # mil-dots
		var o := float(i) * 26.0
		for d in [Vector2(o, 0), Vector2(-o, 0), Vector2(0, o)]:
			_canvas.draw_circle(c + d, 1.6, col)


# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

func _health_color(frac: float) -> Color:
	if frac < LOW_HEALTH:
		return C_RED
	if frac < MID_HEALTH:
		return C_AMBER.lerp(C_RED, (MID_HEALTH - frac) / (MID_HEALTH - LOW_HEALTH))
	return C_GREEN.lerp(C_AMBER, clampf((0.75 - frac) / 0.25, 0.0, 1.0))


func _blink() -> bool:
	return fmod(_pulse, 1.0) < 0.6


func _width(text: String, size: int) -> float:
	return _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## Draws text with a soft drop shadow so it stays readable on any background.
func _text(pos: Vector2, text: String, size: int, color: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	_canvas.draw_string(_font, pos + Vector2(1.5, 1.5), text, align, width, size, Color(0, 0, 0, color.a * 0.7))
	_canvas.draw_string(_font, pos, text, align, width, size, color)
