extends Node
class_name CardPool

const ALL_CARDS := [
	{"id": "attack_1", "name": "Sharper Arrows", "short_label": "+ATK", "description": "Increases arrow damage by 3.", "effect": "attack_power", "value": 3, "cost": 20, "icon": "res://tiny/Tiny Swords (Free Pack)/UI Elements/UI Elements/Icons/Icon_06.png"},
	{"id": "attack_2", "name": "Heavy Draw", "short_label": "+ATK+", "description": "Increases arrow damage by 6.", "effect": "attack_power", "value": 6, "cost": 40, "icon": "res://tiny/Tiny Swords (Free Pack)/UI Elements/UI Elements/Icons/Icon_06.png"},
	{"id": "fire_rate_1", "name": "Fire Rate", "short_label": "FR UP", "description": "Fires 0.15s faster between shots.", "effect": "fire_rate", "value": 0.15, "cost": 30, "icon": "res://tiny/Tiny Swords (Free Pack)/UI Elements/UI Elements/Icons/Icon_07.png"},
	{"id": "volley_1", "name": "Volley Shot", "short_label": "VOLLEY", "description": "Unlocks a periodic volley that fires at every enemy in range simultaneously.", "effect": "volley", "value": 0, "cost": 60, "icon": "res://tiny/Tiny Swords (Free Pack)/UI Elements/UI Elements/Icons/Icon_09.png"},
]

static func get_random_cards(count: int) -> Array:
	var pool: Array = ALL_CARDS.duplicate()
	pool.shuffle()
	return pool.slice(0, min(count, pool.size()))
