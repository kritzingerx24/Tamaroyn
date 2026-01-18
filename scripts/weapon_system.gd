extends Node3D
signal ammo_changed(wep, count)
enum { AUTO, PULSE }
var cur = AUTO
@export var projectile_scene: PackedScene
@export var muzzle_point: Node3D
var ammo = {AUTO: 200, PULSE: 50}
var last_fire = 0.0
func switch_weapon(idx): cur = idx; emit_signal("ammo_changed", "AUTO" if cur==0 else "PULSE", ammo[cur])
func fire(vel):
	var t = Time.get_ticks_msec()/1000.0
	if t - last_fire < 0.2: return
	if ammo[cur] > 0:
		ammo[cur] -= 1
		last_fire = t
		emit_signal("ammo_changed", "AUTO" if cur==0 else "PULSE", ammo[cur])
		if cur == AUTO: 
			var p = projectile_scene.instantiate()
			get_tree().root.add_child(p)
			p.global_transform = muzzle_point.global_transform
			p.linear_velocity = (-muzzle_point.global_transform.basis.z * 100) + vel
func add_ammo(amount):
	ammo[cur] += amount
	emit_signal("ammo_changed", "AUTO" if cur==0 else "PULSE", ammo[cur])
