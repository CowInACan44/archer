extends HBoxContainer

## Shows the combined arrow stock across every tower, since with multiple
## towers there's no single "the" tower to report on. Polls rather than
## wiring signals through every tower, so it keeps working as towers are
## built mid-run without extra bookkeeping.
@onready var count_label: Label = $Count

var _poll_timer: Timer


func _ready() -> void:
	_poll_timer = Timer.new()
	_poll_timer.wait_time = 0.25
	_poll_timer.timeout.connect(_refresh)
	add_child(_poll_timer)
	_poll_timer.start()
	_refresh()


func _refresh() -> void:
	var total := 0
	for tower in get_tree().get_nodes_in_group("tower"):
		if not is_instance_valid(tower):
			continue
		var field: Node = tower.get_node_or_null("ArrowField")
		if field and field.has_method("filled_count"):
			total += field.filled_count()
	count_label.text = "x %d" % total
