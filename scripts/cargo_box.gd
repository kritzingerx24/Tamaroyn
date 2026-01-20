extends RigidBody3D
@export var building_type: int = 0
func _ready(): 
	add_to_group("cargo"); var c=[Color.GREEN,Color.RED,Color.BLUE]; var m=StandardMaterial3D.new(); if building_type<c.size(): m.albedo_color=c[building_type]; $MeshInstance3D.material_override=m
func _on_area_3d_body_entered(b): if b.has_method("pickup_cargo") and b.is_in_group("tank"): if b.pickup_cargo(building_type): queue_free()
