extends Control

## Decorative border ring drawn on top of the circular minimap's live view,
## doubling as a day/night clock: a sun marker rides the top half of the
## ring during Day (left at sunrise, right at sunset) and a moon marker
## rides the bottom half during Night, each positioned by how far the
## current phase has progressed - see DayNightCycle.day_time_left_fraction()
## and .night_time_elapsed_fraction().

## Two-tone bezel (dark outer band + a lighter inner highlight line)
## instead of one thin line, so the minimap reads as a framed object
## rather than a bare circle floating on the HUD.
const RING_OUTER_COLOR := Color(0.18, 0.11, 0.05, 1.0)
const RING_INNER_COLOR := Color(0.55, 0.4, 0.18, 0.9)
const SUN_COLOR := Color(0.98, 0.85, 0.35, 1.0)
const SUN_COLOR_DIM := Color(0.98, 0.85, 0.35, 0.25)
const MOON_COLOR := Color(0.75, 0.8, 0.95, 1.0)
const MOON_COLOR_DIM := Color(0.75, 0.8, 0.95, 0.25)
const MARKER_RADIUS := 6.0


func _ready() -> void:
	set_process(true)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var center := size / 2.0
	var radius := minf(size.x, size.y) / 2.0 - 3.0
	draw_arc(center, radius, 0.0, TAU, 64, RING_OUTER_COLOR, 7.0)
	draw_arc(center, radius - 4.5, 0.0, TAU, 64, RING_INNER_COLOR, 2.0)

	var dnc: Node = get_tree().get_first_node_in_group("day_night_cycle")
	var is_day := true
	var day_fraction := 0.0
	var night_fraction := 0.0
	if dnc:
		if dnc.has_method("is_night"):
			is_day = not dnc.is_night()
		if dnc.has_method("day_time_left_fraction"):
			day_fraction = 1.0 - dnc.day_time_left_fraction()
		if dnc.has_method("night_time_elapsed_fraction"):
			night_fraction = dnc.night_time_elapsed_fraction()

	## Sun sweeps the top half-circle (9 o'clock -> 12 -> 3 o'clock) as Day
	## elapses; moon sweeps the bottom half (3 -> 6 -> 9 o'clock) as Night
	## elapses. Both still draw, dimmed, when their phase isn't active, so
	## the ring always shows where each will pick back up.
	var sun_angle := deg_to_rad(-90.0 + day_fraction * 180.0)
	var moon_angle := deg_to_rad(90.0 + night_fraction * 180.0)
	var sun_pos := center + Vector2(sin(sun_angle), -cos(sun_angle)) * radius
	var moon_pos := center + Vector2(sin(moon_angle), -cos(moon_angle)) * radius

	draw_circle(moon_pos, MARKER_RADIUS, MOON_COLOR if not is_day else MOON_COLOR_DIM)
	draw_circle(sun_pos, MARKER_RADIUS, SUN_COLOR if is_day else SUN_COLOR_DIM)
