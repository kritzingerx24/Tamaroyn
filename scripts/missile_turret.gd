extends "res://scripts/turret_ai.gd"
@export var missile_scene: PackedScene; @export var launch_sound: AudioStreamPlayer3D
func _ready(): fire_rate=3.0; range=250.0; super._ready(); var mat=StandardMaterial3D.new(); mat.albedo_color=Color(0.2,0.2,0.2); $BaseMesh.material_override=mat
func _on_fire(): if is_instance_valid(target) and multiplayer.is_server(): head.look_at(target.global_position, Vector3.UP); fire_missile_rpc.rpc()
@rpc("call_local") func fire_missile_rpc(): if launch_sound: launch_sound.play(); var m=missile_scene.instantiate(); m.team=team; if is_instance_valid(target): m.target=target; get_tree().root.add_child(m); m.global_transform=muzzle.global_transform; m.linear_velocity=muzzle.global_transform.basis.y*20.0; m.timer=0.0