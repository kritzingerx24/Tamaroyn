extends Control

@onready var uplink_panel = $UplinkMenu
@onready var uplink_label = $UplinkMenu/Label

func _ready():
	uplink_panel.visible = false

func toggle_menu(is_open):
	uplink_panel.visible = is_open
	if is_open:
		uplink_label.text = "UPLINK ESTABLISHED\n\n[1] Power Cell\n[2] Turret\n[3] Repair Pad"
