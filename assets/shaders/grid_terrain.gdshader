shader_type spatial;

uniform vec3 grid_color : source_color = vec3(0.0, 1.0, 0.2);
uniform vec3 ground_color : source_color = vec3(0.05, 0.05, 0.05);
uniform float grid_scale = 10.0;
uniform float line_thickness = 0.02;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Planar mapping logic for grid
	vec2 grid_uv = world_pos.xz / grid_scale;
	vec2 grid = abs(fract(grid_uv - 0.5) - 0.5) / fwidth(grid_uv);
	float line = min(grid.x, grid.y);
	
	float grid_mix = 1.0 - smoothstep(0.0, line_thickness, line);
	
	ALBEDO = mix(ground_color, grid_color, grid_mix);
	EMISSION = mix(vec3(0.0), grid_color * 2.0, grid_mix);
}
