extends Camera3D

var speed = 20.0
var mouse_sensitivity = 0.003

func _enter_tree():
	set_multiplayer_authority(name.to_int())

func _ready():
	if is_multiplayer_authority():
		current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event):
	if !is_multiplayer_authority(): return
	
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)
		rotate_x(-event.relative.y * mouse_sensitivity)
		rotation.x = clamp(rotation.x, -1.5, 1.5)

func _process(delta):
	if !is_multiplayer_authority(): return
	
	var velocity = Vector3.ZERO
	if Input.is_action_pressed("move_forward"): velocity -= transform.basis.z
	if Input.is_action_pressed("move_backward"): velocity += transform.basis.z
	if Input.is_action_pressed("turn_left"): velocity -= transform.basis.x
	if Input.is_action_pressed("turn_right"): velocity += transform.basis.x
	if Input.is_action_pressed("jump_jets"): velocity += Vector3.UP
	# Crouch/Down? mapped to ctrl usually, using standard vars
	
	var current_speed = speed
	if Input.is_action_pressed("spectator_speed"): current_speed *= 3.0
	
	global_position += velocity * current_speed * delta
