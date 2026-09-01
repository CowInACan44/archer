extends Node2D

## RTS-style pawn control: left-click a pawn to select it (shift-click to
## add to the selection), then right-click a spot to send the selection
## there, or right-click a tree/rock to assign them to gather it. Selected
## pawns stop their normal auto-gather AI (see Pawn.manual_mode) until
## recalled - see the Pawns HUD tab for Select All/Recall All.

const SELECT_RADIUS := 26.0
const DEFAULT_CLICK_RADIUS := 40.0

var selected_pawns: Array[Node] = []

signal selection_changed(count: int)


func _ready() -> void:
	add_to_group("pawn_controller")


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return

	var world_pos := get_global_mouse_position()

	if event.button_index == MOUSE_BUTTON_LEFT:
		_handle_select_click(world_pos)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_handle_command_click(world_pos)


func _handle_select_click(world_pos: Vector2) -> void:
	var clicked := _find_pawn_near(world_pos)
	var additive := Input.is_key_pressed(KEY_SHIFT)

	if clicked == null:
		if not additive:
			_clear_selection()
		return

	if not additive:
		_clear_selection()

	if clicked in selected_pawns:
		clicked.set_selected(false)
		selected_pawns.erase(clicked)
	else:
		clicked.set_selected(true)
		selected_pawns.append(clicked)

	selection_changed.emit(selected_pawns.size())


func _handle_command_click(world_pos: Vector2) -> void:
	_prune_selection()
	if selected_pawns.is_empty():
		return

	var node := _find_resource_node_near(world_pos)
	for pawn in selected_pawns:
		if not is_instance_valid(pawn):
			continue
		if node:
			pawn.command_gather(node)
		else:
			pawn.command_move_to(world_pos)


func select_all() -> void:
	_clear_selection()
	for pawn in get_tree().get_nodes_in_group("pawn"):
		if is_instance_valid(pawn):
			pawn.set_selected(true)
			selected_pawns.append(pawn)
	selection_changed.emit(selected_pawns.size())


func recall_all() -> void:
	for pawn in get_tree().get_nodes_in_group("pawn"):
		if is_instance_valid(pawn) and pawn.has_method("command_recall"):
			pawn.command_recall()


func _clear_selection() -> void:
	for pawn in selected_pawns:
		if is_instance_valid(pawn):
			pawn.set_selected(false)
	selected_pawns.clear()
	selection_changed.emit(0)


func _prune_selection() -> void:
	selected_pawns = selected_pawns.filter(func(p): return is_instance_valid(p))


func _find_pawn_near(world_pos: Vector2) -> Node:
	var nearest: Node = null
	var nearest_dist := SELECT_RADIUS
	for pawn in get_tree().get_nodes_in_group("pawn"):
		if not is_instance_valid(pawn):
			continue
		var dist: float = world_pos.distance_to(pawn.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = pawn
	return nearest


func _find_resource_node_near(world_pos: Vector2) -> Node:
	var nearest: Node = null
	var nearest_dist := INF
	for node in get_tree().get_nodes_in_group("resource_node"):
		if not is_instance_valid(node):
			continue
		var radius: float = node.click_radius if "click_radius" in node else DEFAULT_CLICK_RADIUS
		var dist: float = world_pos.distance_to(node.global_position)
		if dist <= radius and dist < nearest_dist:
			nearest_dist = dist
			nearest = node
	return nearest
