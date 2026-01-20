shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// Readability shader: colors terrain by height + slope, with a world-space grid.
// This is intentionally "gamey" so you can tell what's what while we build systems.

uniform float sea_level = -40.0;
uniform float snow_level = 420.0;
uniform float grid_meters = 100.0;
uniform float grid_line_width = 0.02; // normalized per-cell
uniform float grid_strength = 0.25;   // 0..1

vec3 height_band(float h) {
	if (h < sea_level) {
		return vec3(0.02, 0.08, 0.18); // deep water
	}
	if (h < sea_level + 12.0) {
		return vec3(0.46, 0.42, 0.24); // sand
	}
	if (h < 120.0) {
		return vec3(0.14, 0.34, 0.14); // grass
	}
	if (h < 260.0) {
		return vec3(0.22, 0.26, 0.18); // scrub
	}
	if (h < snow_level) {
		return vec3(0.36, 0.34, 0.32); // rock
	}
	return vec3(0.86, 0.86, 0.88); // snow
}

float grid_line(float coord) {
	float cell = coord / max(grid_meters, 0.001);
	float f = abs(fract(cell) - 0.5);
	float aa = fwidth(cell) * 1.5;
	return 1.0 - smoothstep(grid_line_width, grid_line_width + aa, f);
}

void fragment() {
	float h = WORLD_POSITION.y;
	vec3 base = height_band(h);

	// Darken based on slope.
	float up = clamp(dot(normalize(WORLD_NORMAL), vec3(0.0, 1.0, 0.0)), 0.0, 1.0);
	float slope = 1.0 - up;
	base *= (1.0 - slope * 0.35);

	// World grid overlay.
	float gx = grid_line(WORLD_POSITION.x);
	float gz = grid_line(WORLD_POSITION.z);
	float g = max(gx, gz) * grid_strength;
	base = mix(base, vec3(0.0), g);

	ALBEDO = base;
	ROUGHNESS = 0.95;
	METALLIC = 0.0;
}
