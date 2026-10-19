shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;
// The crowd: every fan sways a little, and when the park gets excited they stand up and bounce.
// One MultiMesh, no per-fan code: the phase comes from where the fan sits.

uniform float excite : hint_range(0.0, 1.0) = 0.0;   // 0 sitting, 1 on their feet cheering
uniform float anchor_y = 0.0;                         // height of this mesh's center above the fan's body center (heads use 0.62)

varying vec3 tint;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
}

void vertex() {
	tint = srgb_to_linear(COLOR.rgb);
	vec3 wp = MODEL_MATRIX[3].xyz;
	float phase = fract(sin(dot(wp.xz, vec2(12.9898, 78.233))) * 43758.5453) * 6.2831;
	float idle = 0.012 * sin(TIME * 1.3 + phase);
	float bounce = excite * 0.09 * (0.5 + 0.5 * sin(TIME * 7.5 + phase * 3.0));
	float stand = excite * 0.12 * (VERTEX.y + anchor_y + 0.5);
	VERTEX.y += idle + bounce + stand;
	VERTEX.x += excite * 0.03 * sin(TIME * 5.0 + phase);
}

void fragment() {
	ALBEDO = tint;
	ROUGHNESS = 1.0;
}
