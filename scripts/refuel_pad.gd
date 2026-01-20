extends "res://scripts/building_base.gd"
func _ready(): add_to_group("refuel_pad"); super._ready()
func _on_area_body_entered(b): if b.has_method("refuel"): b.refuel(5)