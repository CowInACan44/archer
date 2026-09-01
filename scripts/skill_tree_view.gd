extends Control
class_name SkillTreeView

## Renders one branching node-graph per Skills tab category (see
## GameManager.SKILLS_UI_TREE) with its own independent pan/zoom, replacing
## the old flat list of text buttons. Node positions come from each entry's
## hand-placed col/row grid coordinates rather than a computed auto-layout
## algorithm, so branch shapes stay predictable and readable no matter how
## many nodes a category ends up with.

signal action_requested(action_id: String)

const NODE_SIZE := 56.0
const COLUMN_SPACING := 130.0
const ROW_SPACING := 110.0
## Wood's tree uses a negative column (see SKILLS_UI_TREE) - shifting every
## node right by this keeps it from landing off Canvas's left edge.
const X_OFFSET := 260.0
const Y_OFFSET := 50.0
const CANVAS_SIZE := Vector2(760.0, 480.0)

const COLOR_LEVEL := Color(0.35, 0.55, 0.85)
const COLOR_LOCKED := Color(0.32, 0.32, 0.32)
const COLOR_AVAILABLE := Color(0.75, 0.6, 0.2)
const COLOR_UNLOCKED := Color(0.35, 0.75, 0.4)
const COLOR_ACTION := Color(0.6, 0.35, 0.75)
const LINE_COLOR := Color(0.5, 0.45, 0.4, 0.8)
const LINE_WIDTH := 3.0

const MIN_ZOOM := 0.55
const MAX_ZOOM := 1.5
const ZOOM_STEP := 0.1

@onready var clip_area: Control = $ClipArea
@onready var canvas: Control = $ClipArea/Canvas
@onready var tooltip_panel: PanelContainer = $TooltipPanel
@onready var tooltip_label: Label = $TooltipPanel/MarginContainer/TooltipLabel

var _category: String = ""
var _entries_by_id: Dictionary = {}
var _positions: Dictionary = {}
var _buttons: Dictionary = {}

var _dragging := false
var _drag_start_mouse: Vector2
var _drag_start_canvas_pos: Vector2


func _ready() -> void:
	tooltip_panel.visible = false
	var tooltip_style := StyleBoxFlat.new()
	tooltip_style.bg_color = Color(0.1, 0.08, 0.06, 0.95)
	tooltip_style.border_color = Color(0.6, 0.5, 0.3, 1.0)
	tooltip_style.set_border_width_all(2)
	tooltip_style.set_corner_radius_all(6)
	tooltip_style.set_content_margin_all(2)
	tooltip_panel.add_theme_stylebox_override("panel", tooltip_style)
	canvas.custom_minimum_size = CANVAS_SIZE
	canvas.size = CANVAS_SIZE
	clip_area.gui_input.connect(_on_gui_input)

	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm:
		gm.incrementals_changed.connect(_on_data_changed)
		gm.skill_tree_changed.connect(_on_data_changed)


## Full rebuild - clears and re-lays-out every node, resets pan/zoom.
## Called when the player switches to a different category.
func build_tree(category: String) -> void:
	_category = category
	canvas.position = Vector2.ZERO
	canvas.scale = Vector2.ONE
	tooltip_panel.visible = false
	for child in canvas.get_children():
		child.queue_free()
	_entries_by_id.clear()
	_positions.clear()
	_buttons.clear()

	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	var entries: Array = gm.SKILLS_UI_TREE.get(category, []) if gm else []
	for entry in entries:
		_entries_by_id[entry.id] = entry
		_positions[entry.id] = Vector2(X_OFFSET + entry.col * COLUMN_SPACING, Y_OFFSET + entry.row * ROW_SPACING)
	for entry in entries:
		_buttons[entry.id] = _make_node_button(entry)

	_refresh_node_states()
	_redraw_lines()


## Lighter-weight refresh (levels/unlocks changed elsewhere) - updates
## colors/text/disabled state without destroying buttons or resetting the
## player's current pan/zoom.
func _on_data_changed() -> void:
	if _category != "":
		_refresh_node_states()


func _make_node_button(entry: Dictionary) -> Button:
	var button := Button.new()
	button.name = entry.id
	button.custom_minimum_size = Vector2(NODE_SIZE, NODE_SIZE)
	button.size = Vector2(NODE_SIZE, NODE_SIZE)
	button.position = _positions[entry.id] - Vector2(NODE_SIZE, NODE_SIZE) * 0.5
	button.clip_text = true
	button.mouse_filter = Control.MOUSE_FILTER_PASS  # let wheel/middle-drag bubble up to ClipArea for pan/zoom
	button.add_theme_font_size_override("font_size", 10)

	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(int(NODE_SIZE / 2))
	style.set_border_width_all(3)
	style.border_color = Color(0, 0, 0, 0.55)
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, style)
	button.set_meta("style", style)

	button.mouse_entered.connect(_on_node_hover.bind(entry.id))
	button.mouse_exited.connect(_on_node_unhover)
	button.pressed.connect(_on_node_pressed.bind(entry.id))

	canvas.add_child(button)
	return button


func _refresh_node_states() -> void:
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm == null:
		return
	for id in _entries_by_id:
		var entry: Dictionary = _entries_by_id[id]
		var button: Button = _buttons[id]
		var style: StyleBoxFlat = button.get_meta("style")
		match entry.kind:
			"level":
				var level: int = gm.get(entry.level_prop)
				button.text = "%s\nLv %d" % [entry.name, level]
				button.disabled = false
				style.bg_color = COLOR_LEVEL
			"action":
				button.text = entry.name
				button.disabled = false
				style.bg_color = COLOR_ACTION
			"node":
				var unlocked: bool = gm.skill_node_unlocked(id)
				var available: bool = gm.skill_node_available(entry)
				button.disabled = unlocked or not available
				button.text = ("%s\n(done)" % entry.name) if unlocked else entry.name
				if unlocked:
					style.bg_color = COLOR_UNLOCKED
				elif available:
					style.bg_color = COLOR_AVAILABLE
				else:
					style.bg_color = COLOR_LOCKED


func _redraw_lines() -> void:
	var lines: Array[Dictionary] = []
	for id in _entries_by_id:
		var entry: Dictionary = _entries_by_id[id]
		if entry.requires == "" or not _positions.has(entry.requires):
			continue
		lines.append({
			"from": _positions[entry.requires],
			"to": _positions[id],
			"color": LINE_COLOR,
			"width": LINE_WIDTH,
		})
	canvas.set_lines(lines)


func _on_node_pressed(id: String) -> void:
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm == null:
		return
	var entry: Dictionary = _entries_by_id[id]
	var ok := true
	match entry.kind:
		"level":
			ok = gm.call(entry.buy)
		"node":
			ok = gm.buy_skill_node(_category, id)
		"action":
			action_requested.emit(entry.action_id)

	if not ok:
		var button: Button = _buttons[id]
		var tween := create_tween()
		tween.tween_property(button, "modulate", Color(1, 0.4, 0.4), 0.1)
		tween.tween_property(button, "modulate", Color(1, 1, 1), 0.15)
	_refresh_node_states()
	_show_tooltip(id)


func _on_node_hover(id: String) -> void:
	_show_tooltip(id)


func _on_node_unhover() -> void:
	tooltip_panel.visible = false


func _show_tooltip(id: String) -> void:
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm == null or not _entries_by_id.has(id):
		return
	var entry: Dictionary = _entries_by_id[id]
	var lines: Array[String] = [entry.name, entry.desc]
	match entry.kind:
		"level":
			lines.append("Cost: %s" % gm.format_cost(gm.call(entry.cost_fn)))
		"node":
			if gm.skill_node_unlocked(id):
				lines.append("Unlocked")
			elif not gm.skill_node_available(entry):
				var req: Dictionary = _entries_by_id.get(entry.requires, {})
				lines.append("Locked - unlock %s first" % req.get("name", entry.requires))
			else:
				lines.append("Cost: %s" % gm.format_cost(entry.cost))
		"action":
			lines.append("Cost: ~%s" % gm.format_cost(entry.cost))

	tooltip_label.text = "\n".join(lines)
	tooltip_panel.visible = true
	var button: Button = _buttons[id]
	tooltip_panel.position = (button.global_position - global_position) + Vector2(NODE_SIZE + 8.0, -8.0)
	await get_tree().process_frame
	if not tooltip_panel.visible:
		return
	var max_x: float = size.x - tooltip_panel.size.x - 4.0
	var max_y: float = size.y - tooltip_panel.size.y - 4.0
	tooltip_panel.position.x = clampf(tooltip_panel.position.x, 4.0, maxf(4.0, max_x))
	tooltip_panel.position.y = clampf(tooltip_panel.position.y, 4.0, maxf(4.0, max_y))


## Scroll wheel zooms the tree toward the mouse, middle-drag pans it -
## isolated to this panel via ClipArea's own gui_input (Control mouse
## events stop here rather than bubbling out to the world), so this never
## fights with the main camera's own scroll-to-zoom the way the Volley
## Shot reticle rotation used to (see camera_2d.gd/hotbar.gd).
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_by(ZOOM_STEP, event.position)
			clip_area.accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_by(-ZOOM_STEP, event.position)
			clip_area.accept_event()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed
			if _dragging:
				_drag_start_mouse = event.position
				_drag_start_canvas_pos = canvas.position
			clip_area.accept_event()
	elif event is InputEventMouseMotion and _dragging:
		canvas.position = _drag_start_canvas_pos + (event.position - _drag_start_mouse)
		clip_area.accept_event()


func _zoom_by(amount: float, around: Vector2) -> void:
	var old_scale: float = canvas.scale.x
	var new_scale: float = clampf(old_scale + amount, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(new_scale, old_scale):
		return
	var local_before: Vector2 = (around - canvas.position) / old_scale
	canvas.scale = Vector2(new_scale, new_scale)
	canvas.position = around - local_before * new_scale
