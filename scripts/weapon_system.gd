extends Node3D

signal ammo_changed(wep, count)

enum { AUTO, PULSE }
var cur = AUTO

@export var projectile_scene: PackedScene
@export var muzzle_point: Node3D
@export var shoot_sound: AudioStreamPlayer3D
@export var muzzle_flash_light: OmniLight3D

var ammo = {AUTO: 200, PULSE: 50}
var last_fire = 0.0

func _ready():
	if muzzle_flash_light: muzzle_flash_light.visible = false

func switch_weapon(idx): 
	cur = idx
	emit_signal("ammo_changed", "AUTO" if cur==0 else "PULSE", ammo[cur])

func fire(vel):
	var t = Time.get_ticks_msec()/1000.0
	if t - last_fire < 0.2: return
	
	if ammo[cur] > 0:
		ammo[cur] -= 1
		last_fire = t
		emit_signal("ammo_changed", "AUTO" if cur==0 else "PULSE", ammo[cur])
		
		# Audio
		if shoot_sound:
			shoot_sound.pitch_scale = randf_range(0.9, 1.1)
			shoot_sound.play()
			
		# Visuals
		do_muzzle_flash()
		
		# Camera Shake (Global check if this is player)
		var tank = get_parent()
		if tank.is_in_group("player"):
			var cam = get_viewport().get_camera_3d()
			if cam and cam.has_method("shake"):
				cam.shake(0.2) # Small shake on fire
		
		if cur == AUTO: 
			var p = projectile_scene.instantiate()
			get_tree().root.add_child(p)
			p.global_transform = muzzle_point.global_transform
			p.linear_velocity = (-muzzle_point.global_transform.basis.z * 100) + vel

func do_muzzle_flash():
	if muzzle_flash_light:
		muzzle_flash_light.visible = true
		await get_tree().create_timer(0.05).timeout
		muzzle_flash_light.visible = false

func add_ammo(amount):
	ammo[cur] += amount
	emit_signal("ammo_changed", "AUTO" if cur==0 else "PULSE", ammo[cur])
