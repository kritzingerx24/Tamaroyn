extends WorldEnvironment

# Themes based on your files: Sunset, Aurora, Storm
var themes = [
	{ "top": Color(0.1, 0.0, 0.2), "horizon": Color(0.8, 0.4, 0.1), "ground": Color(0.1, 0.1, 0.1) }, # Sunset
	{ "top": Color(0.0, 0.2, 0.1), "horizon": Color(0.0, 0.8, 0.4), "ground": Color(0.0, 0.1, 0.0) }, # Aurora
	{ "top": Color(0.05, 0.05, 0.1), "horizon": Color(0.2, 0.2, 0.3), "ground": Color(0.05, 0.05, 0.05) }  # Storm
]

var current_idx = 0

func _ready():
	update_sky()

func _input(event):
	if event.is_action_pressed("cycle_sky"):
		current_idx = (current_idx + 1) % themes.size()
		update_sky()

func update_sky():
	if environment and environment.sky and environment.sky.sky_material:
		var mat = environment.sky.sky_material as ProceduralSkyMaterial
		var t = themes[current_idx]
		
		# Animate transition? For now, snap
		mat.sky_top_color = t["top"]
		mat.sky_horizon_color = t["horizon"]
		mat.ground_bottom_color = t["ground"]
		mat.ground_horizon_color = t["horizon"]
