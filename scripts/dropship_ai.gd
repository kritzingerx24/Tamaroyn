extends Node3D
var target_pos; var cargo_type; var state=0
func setup_delivery(p,t): target_pos=p; cargo_type=t; global_position=p+Vector3(0,100,0)
func _process(d):
	if state==0:
		global_position=global_position.move_toward(target_pos+Vector3(0,10,0),30*d)
		if global_position.distance_to(target_pos+Vector3(0,10,0))<1:
			if multiplayer.is_server(): get_tree().current_scene.get_node("BuildingSpawner").spawn_box(cargo_type, target_pos)
			state=1
	elif state==1: global_position+=Vector3.UP*30*d; if global_position.y>150: queue_free()
