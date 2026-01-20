shader_type spatial;
uniform vec3 grid_color : source_color = vec3(0.0, 1.0, 0.2);
uniform vec3 ground_color : source_color = vec3(0.05, 0.05, 0.05);
uniform float grid_scale = 10.0; uniform float line_thickness = 0.02;
uniform sampler2D map_data : filter_nearest; uniform float map_size_world = 480.0;
varying vec3 world_pos;
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 grid_uv = world_pos.xz / grid_scale;
	vec2 grid = abs(fract(grid_uv - 0.5) - 0.5) / fwidth(grid_uv);
	float line = min(grid.x, grid.y);
	float grid_mix = 1.0 - smoothstep(0.0, line_thickness, line);
	vec2 map_uv = (world_pos.xz + (map_size_world * 0.5)) / map_size_world;
	vec3 territory_color = ground_color;
	if (map_uv.x >= 0.0 && map_uv.x <= 1.0 && map_uv.y >= 0.0 && map_uv.y <= 1.0) {
		float id = texture(map_data, map_uv).r;
		if (id > 0.3 && id < 0.6) territory_color = mix(ground_color, vec3(0.5, 0.0, 0.0), 0.4);
		else if (id > 0.7) territory_color = mix(ground_color, vec3(0.0, 0.0, 0.5), 0.4);
	}
	ALBEDO = mix(territory_color, grid_color, grid_mix);
	EMISSION = mix(vec3(0.0), grid_color * 2.0, grid_mix);
}
