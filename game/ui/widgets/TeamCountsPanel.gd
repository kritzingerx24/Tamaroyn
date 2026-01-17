extends Control

# Top-center team player counts. Left is BLUE team (team=1), right is RED team (team=0).

@onready var blue_icon: TextureRect = $Center/HBox/BlueIcon
@onready var red_icon: TextureRect = $Center/HBox/RedIcon
@onready var blue_label: Label = $Center/HBox/BlueCount
@onready var red_label: Label = $Center/HBox/RedCount

var _blue: int = 0
var _red: int = 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if blue_icon != null:
		blue_icon.texture = load("res://assets/wulfram_textures/extracted/blue_crest.png")
	if red_icon != null:
		red_icon.texture = load("res://assets/wulfram_textures/extracted/red_crest.png")
	# Slightly tint the counts to match team colors.
	if blue_label != null:
		blue_label.modulate = Color(0.55, 0.75, 1.0, 1.0)
	if red_label != null:
		red_label.modulate = Color(1.0, 0.55, 0.55, 1.0)
	set_counts(0, 0)

func set_counts(blue_count: int, red_count: int) -> void:
	if blue_count == _blue and red_count == _red:
		return
	_blue = max(0, blue_count)
	_red = max(0, red_count)
	if blue_label != null:
		blue_label.text = str(_blue)
	if red_label != null:
		red_label.text = str(_red)
