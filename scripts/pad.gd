extends StaticBody3D
enum {REPAIR, REFUEL}
@export var type = REPAIR
func _on_area_body_entered(body):
	if body.has_method("repair"):
		if type == REPAIR: body.repair(20)
		else: body.refuel(50)
