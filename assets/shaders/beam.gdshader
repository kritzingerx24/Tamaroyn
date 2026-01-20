shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec3 color : source_color = vec3(0.0, 1.0, 0.0);
uniform float speed = 5.0;

void fragment() {
	float alpha = 1.0 - abs(UV.y - 0.5) * 2.0;
	float noise = sin(UV.x * 20.0 + TIME * speed) * 0.5 + 0.5;
	ALBEDO = color;
	ALPHA = alpha * noise;
}
