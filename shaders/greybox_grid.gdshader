// World-space grid for greyboxing.
//
// Grid lines are computed from WORLD position, not UVs, so every block in the
// arena shares one continuous grid no matter how it is scaled or rotated. That
// makes distances readable by eye while blocking out a level, which matters a
// lot when you are tuning jump gaps.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 base_color : source_color = vec3(0.30, 0.31, 0.34);
uniform vec3 line_color : source_color = vec3(0.16, 0.17, 0.20);
uniform vec3 up_tint : source_color = vec3(1.06, 1.06, 1.08);
uniform float cell_size = 1.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.92;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Cheap triplanar: project onto the two axes the face is most parallel to.
	vec3 n = abs(normalize(world_normal));
	vec2 uv;
	if (n.y >= n.x && n.y >= n.z) {
		uv = world_position.xz;
	} else if (n.x >= n.z) {
		uv = world_position.zy;
	} else {
		uv = world_position.xy;
	}

	// fwidth keeps the line one pixel wide at any distance, so the grid does
	// not turn into moire noise across a 100 m sightline.
	vec2 grid = uv / cell_size;
	vec2 distance_to_line = abs(fract(grid - 0.5) - 0.5) / fwidth(grid);
	float line = 1.0 - clamp(min(distance_to_line.x, distance_to_line.y), 0.0, 1.0);

	vec3 albedo = mix(base_color, line_color, line);
	// Lift upward faces slightly so floors read apart from walls under flat light.
	albedo *= mix(vec3(1.0), up_tint, clamp(world_normal.y, 0.0, 1.0));
	ALBEDO = albedo;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.2;
}
