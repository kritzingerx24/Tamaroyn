extends StaticBody3D
func _on_area_body_entered(b): if b.has_method('repair'): b.repair(20)