extends Control
@export var tank_path: NodePath
@onready var hp_bar = $Panel/VBox/HealthBar
@onready var ammo_lbl = $Panel/VBox/AmmoLabel
func _ready():
	var tank = get_node(tank_path)
	tank.stats_changed.connect(func(h,m): hp_bar.max_value=m; hp_bar.value=h)
	tank.weapon_sys.ammo_changed.connect(func(n,c): ammo_lbl.text = n + ": " + str(c))
