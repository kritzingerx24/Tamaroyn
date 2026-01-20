extends "res://scripts/building_base.gd"
@onready var anim = $AnimationPlayer; @onready var audio = $AudioStreamPlayer3D
func _ready():
	super._ready(); var mat = StandardMaterial3D.new(); mat.albedo_color = Color(0.5, 0, 0.5); mat.emission_enabled = true; mat.emission = Color(0.5, 0, 0.5); $MeshInstance3D.material_override = mat; if audio: audio.play()
func _on_area_3d_body_entered(body): if "team" in body and body.team == team: if body.has_method("set_cloaked"): body.set_cloaked(true)
func _on_area_3d_body_exited(body): if "team" in body and body.team == team: if body.has_method("set_cloaked"): body.set_cloaked(false)
