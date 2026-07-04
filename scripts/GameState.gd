# GameState.gd — Autoload singleton
# Tracks glow coins, inventory, and unlocked plant types.
extends Node

signal coins_changed(amount: int)
signal inventory_changed

var coins: int = 10 :
	set(v):
		coins = v
		coins_changed.emit(coins)

# Plant catalog: id -> {name, cost, color, glow_color, bloom_time, value}
const PLANTS := {
	"sparkle": {
		"name": "Sparklebud",
		"cost": 3,
		"petal_color": Color(1.0, 0.82, 0.4),
		"glow_color": Color(1.0, 0.85, 0.3),
		"bloom_time": 8.0,
		"value": 5,
	},
	"moon": {
		"name": "Moonblossom",
		"cost": 8,
		"petal_color": Color(0.7, 0.8, 1.0),
		"glow_color": Color(0.5, 0.7, 1.0),
		"bloom_time": 15.0,
		"value": 12,
	},
	"ember": {
		"name": "Emberlily",
		"cost": 15,
		"petal_color": Color(1.0, 0.4, 0.3),
		"glow_color": Color(1.0, 0.3, 0.15),
		"bloom_time": 25.0,
		"value": 25,
	},
}

var selected_plant: String = "sparkle"
