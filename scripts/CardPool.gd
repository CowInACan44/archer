extends Node
class_name CardPool

const ALL_CARDS := [
	{"id": "attack_1", "name": "Sharper Arrows", "short_label": "+ATK", "description": "Increases arrow damage by 3.", "effect": "attack_power", "value": 3},
	{"id": "attack_2", "name": "Heavy Draw", "short_label": "+ATK+", "description": "Increases arrow damage by 6.", "effect": "attack_power", "value": 6},
	{"id": "fire_rate_1", "name": "Fire Rate", "short_label": "FR ↑", "description": "Fires 0.15s faster between shots.", "effect": "fire_rate", "value": 0.15, "icon_frames": "res://icons/firerate.tres"},
	{"id": "volley_1", "name": "Volley Shot", "short_label": "VOLLEY", "description": "Unlocks a periodic volley that fires at every enemy in range simultaneously.", "effect": "volley", "value": 0},
]

static func get_random_cards(count: int) -> Array:
	var pool: Array = ALL_CARDS.duplicate()
	pool.shuffle()
	return pool.slice(0, min(count, pool.size()))
