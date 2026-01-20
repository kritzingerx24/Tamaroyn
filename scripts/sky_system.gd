extends WorldEnvironment

func _ready():
	if environment:
		environment.background_mode = Environment.BG_SKY
		
		var sky = Sky.new()
		var mat = ProceduralSkyMaterial.new()
		
		# Alien Day: Deep Blue Sky, Bright Horizon
		mat.sky_top_color = Color(0.05, 0.1, 0.3)
		mat.sky_horizon_color = Color(0.4, 0.6, 0.8)
		mat.ground_bottom_color = Color(0.1, 0.1, 0.1)
		mat.ground_horizon_color = Color(0.4, 0.6, 0.8)
		
		sky.sky_material = mat
		environment.sky = sky
		
		# Lighting
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		environment.ambient_light_energy = 1.0
		environment.tonemap_mode = Environment.TONE_MAPPER_ACES
		environment.ssao_enabled = true # Ambient Occlusion for depth
		environment.glow_enabled = true # Bloom for shots
