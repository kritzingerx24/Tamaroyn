shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

// Terrain readability shader (Wulfram-style): blends grass/dirt/rock using slope + height,
// with added macro-variation and optional contour lines to reduce tiling and improve depth cues.

uniform sampler2D tex_grass : source_color;
uniform sampler2D tex_dirt : source_color;
uniform sampler2D tex_rock : source_color;

// Micro tiling (close detail). Larger value -> more tiling.
uniform float uv_scale_micro = 0.035;
// Macro tiling (far variation). Larger value -> more tiling.
uniform float uv_scale_macro = 0.010;

// How much of the macro layer to blend in at distance (0..1).
uniform float macro_strength = 0.40;
// Camera distance range where macro blend fades in.
uniform float macro_distance_start = 250.0;
uniform float macro_distance_end = 900.0;

// Rock by slope.
uniform float rock_slope_start = 0.45; // 0..1 (0=flat)
uniform float rock_slope_end = 0.78;

// Dirt/grass by height (world Y).
uniform float dirt_height = 25.0;
uniform float grass_height = 120.0;

// Optional contour lines (improves elevation readability).
uniform bool contours_enabled = true;
uniform float contour_period = 25.0;    // world meters between contour bands
uniform float contour_width = 0.06;     // 0..0.5 normalized within a band
uniform float contour_strength = 0.10;  // 0..1

// Simple "slope AO" darkening (improves shape perception).
uniform float slope_ao_strength = 0.18;

float hash12(vec2 p) {
    // Cheap stable hash (0..1)
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453123);
}

vec4 triplanar_sample_scaled(sampler2D tex, vec3 world_pos, vec3 world_normal, float uv_scale) {
    vec3 n = abs(world_normal);
    // Avoid division by 0.
    n = max(n, vec3(0.0001));
    n /= (n.x + n.y + n.z);

    vec2 uv_x = world_pos.zy * uv_scale;
    vec2 uv_y = world_pos.xz * uv_scale;
    vec2 uv_z = world_pos.xy * uv_scale;

    vec4 cx = texture(tex, uv_x);
    vec4 cy = texture(tex, uv_y);
    vec4 cz = texture(tex, uv_z);

    return cx * n.x + cy * n.y + cz * n.z;
}

float contour_mask(float h) {
    // Returns 0..1 where 1 means "on contour line"
    float period = max(contour_period, 0.001);
    float cell = h / period;
    float f = abs(fract(cell) - 0.5);
    float aa = fwidth(cell) * 1.5;
    float line = 1.0 - smoothstep(contour_width, contour_width + aa, f);
    return line;
}

void fragment() {
    vec3 wp = WORLD_POSITION;
    vec3 wn = normalize(NORMAL);

    // Slope weight for rock (0 = flat, 1 = vertical).
    float slope = 1.0 - clamp(dot(wn, vec3(0.0, 1.0, 0.0)), 0.0, 1.0);

    float rock_w = smoothstep(rock_slope_start, rock_slope_end, slope);

    // Height-based dirt vs grass.
    float dirt_w = 1.0 - smoothstep(dirt_height, grass_height, wp.y);
    dirt_w *= (1.0 - rock_w);

    float grass_w = 1.0 - rock_w - dirt_w;
    grass_w = clamp(grass_w, 0.0, 1.0);

    // Micro layer
    vec4 micro_grass = triplanar_sample_scaled(tex_grass, wp, wn, uv_scale_micro);
    vec4 micro_dirt  = triplanar_sample_scaled(tex_dirt,  wp, wn, uv_scale_micro);
    vec4 micro_rock  = triplanar_sample_scaled(tex_rock,  wp, wn, uv_scale_micro);
    vec3 micro_alb = micro_grass.rgb * grass_w + micro_dirt.rgb * dirt_w + micro_rock.rgb * rock_w;

    // Macro layer (same textures, lower tiling)
    vec4 macro_grass = triplanar_sample_scaled(tex_grass, wp, wn, uv_scale_macro);
    vec4 macro_dirt  = triplanar_sample_scaled(tex_dirt,  wp, wn, uv_scale_macro);
    vec4 macro_rock  = triplanar_sample_scaled(tex_rock,  wp, wn, uv_scale_macro);
    vec3 macro_alb = macro_grass.rgb * grass_w + macro_dirt.rgb * dirt_w + macro_rock.rgb * rock_w;

    float dist = length(CAMERA_POSITION_WORLD - wp);
    float t = smoothstep(macro_distance_start, macro_distance_end, dist);
    float n = hash12(wp.xz * 0.02);
    float macro_w = clamp(t * macro_strength * (0.65 + 0.35 * n), 0.0, 1.0);

    vec3 albedo = mix(micro_alb, macro_alb, macro_w);

    // Slope AO (darken steeper slopes slightly)
    albedo *= (1.0 - slope * slope_ao_strength);

    // Contours
    if (contours_enabled) {
        float line = contour_mask(wp.y);
        albedo *= (1.0 - line * contour_strength);
    }

    ALBEDO = albedo;
    ROUGHNESS = 0.95;
    METALLIC = 0.0;
}
