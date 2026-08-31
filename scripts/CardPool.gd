extends Node
class_name CardPool

## min_wave gates when a card can appear at all, so the merchant's stock
## grows over a run instead of dangling a 60-gold card in front of you on
## wave 1 when gold barely trickles in yet.
const ALL_CARDS := [
	{"id": "free_start", "name": "Merchant's Sample", "short_label": "FREE", "description": "A small taste of the goods - increases arrow damage by 1.", "effect": "attack_power", "value": 1, "cost": 0, "min_wave": 1, "icon": "res://tiny/Tiny Swords (Free Pack)/UI Elements/UI Elements/Icons/Icon_04.png"},
	{"id": "attack_1", "name": "Sharper Arrows", "short_label": "+ATK", "description": "Increases arrow damage by 3.", "effect": "attack_power", "value": 3, "cost": 20, "min_wave": 1, "icon": "res://tiny/Tiny Swords (Free Pack)/UI Elements/UI Elements/Icons/Icon_06.png"},
	{"id": "fire_rate_1", "name": "Fire Rate", "short_label": "FR UP", "description": "Fires 0.15s faster between shots.", "effect": "fire_rate", "value": 0.15, "cost": 30, "min_wave": 2, "icon": "res://tiny/Tiny Swords (Free Pack)/UI Elements/UI Elements/Icons/Icon_07.png"},
	{"id": "attack_2", "name": "Heavy Draw", "short_label": "+ATK+", "description": "Increases arrow damage by 6.", "effect": "attack_power", "value": 6, "cost": 40, "min_wave": 3, "icon": "res://tiny/Tiny Swords (Free Pack)/UI Elements/UI Elements/Icons/Icon_06.png"},
	{"id": "volley_1", "name": "Volley Shot", "short_label": "VOLLEY", "description": "Unlocks a periodic volley that fires at every enemy in range simultaneously.", "effect": "volley", "value": 0, "cost": 60, "min_wave": 5, "icon": "res://tiny/Tiny Swords (Free Pack)/UI Elements/UI Elements/Icons/Icon_09.png"},
]

static func get_random_cards(count: int, wave: int = 1) -> Array:
	var pool: Array = ALL_CARDS.filter(func(c): return wave >= c.get("min_wave", 1))
	pool.shuffle()
	return pool.slice(0, min(count, pool.size()))
