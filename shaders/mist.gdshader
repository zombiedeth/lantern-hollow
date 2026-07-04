// Lantern Hollow — drifting mist overlay.
// Web-safe: NO hint_screen_texture. Pure UV-based animated noise rendered
// onto a ColorRect. Soft, low-opacity, behind the gameplay layer.
// Renderer: gl_compatibility (Godot web export).
shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float time = 0.0;
uniform vec4 mist_color : source_color = vec4(0.42, 0.55, 0.78, 0.10);
uniform float speed = 0.06;
uniform float density : hint_range(0.0, 2.0) = 0.85;

// Cheap value-noise from sin/cos layering. Smooth enough for a soft drift.
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = sin(dot(i, vec2(12.9898, 78.233))) * 43758.5453;
	float b = sin(dot(i + vec2(1.0, 0.0), vec2(12.9898, 78.233))) * 43758.5453;
	float c = sin(dot(i + vec2(0.0, 1.0), vec2(12.9898, 78.233))) * 43758.5453;
	float d2 = sin(dot(i + vec2(1.0, 1.0), vec2(12.9898, 78.233))) * 43758.5453;
	a = fract(a); b = fract(b); c = fract(c); d2 = fract(d2);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d2, u.x), u.y);
}

void fragment() {
	// Two layered noise fields, drifting in different directions.
	vec2 uv = UV * vec2(2.6, 3.4);
	vec2 d1 = vec2(time * speed, time * speed * 0.6);
	vec2 d2 = vec2(-time * speed * 0.4, time * speed * 0.25);
	float n = vnoise(uv + d1) * 0.65 + vnoise(uv * 1.7 + d2) * 0.35;

	// Vertical falloff: thicker at the bottom (near the planted beds).
	float v = smoothstep(-0.1, 1.1, UV.y);
	float bottom = 1.0 - (1.0 - v) * 0.6;

	float a = n * density * bottom * mist_color.a;
	COLOR = vec4(mist_color.rgb, a);
}
