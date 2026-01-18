extends WorldEnvironment
var themes = [ { "top": Color(0.1,0,0.2), "horizon": Color(0.8,0.4,0.1), "ground": Color(0.1,0.1,0.1) } ]
func _ready():
	if environment and environment.sky:
		environment.sky.sky_material.sky_top_color = themes[0]["top"]
