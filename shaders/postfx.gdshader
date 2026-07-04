// Lantern Hollow — atmosphere overlay shader.
// Web-safe: NO hint_screen_texture. This shader does NOT sample the screen.
// It's a pure additive overlay shaped by a normalized gradient over the canvas,
// used as a ColorRect behind everything in the atmosphere layer.
// Renderer: gl_compatibility (Godot web export).
shader_type canvas_item;
render_mode unshaded, blend_add;

uniform float time = 0.0;
uniform vec4 inner_color : source_color = vec4(0.35, 0.18, 0.55, 0.18);
uniform vec4 outer_color : source_color = vec4(0.04, 0.02, 0.10, 0.00);
uniform float warmth : hint_range(0.0, 1.0) = 0.15;

// Soft radial "scene warmth" tint. Brightest in the centre of the canvas,
// fading toward the edges. Composed of multiple radial lobes so it does
// not look like a hard circle.
void fragment() {
	vec2 d = SCREEN_UV - vec2(0.5, 0.45);  // bias slightly above centre, where the garden sits
	float r = length(d * vec2(1.6, 1.0));   // stretch vertically a touch

	// Two soft lobes — one warm-tinted, one cool-tinted — to give the scene
	// variation rather than a flat halo.
	float warm_lobe = exp(-r * 2.4) * (0.6 + 0.4 * sin(time * 0.6));
	float cool_lobe = exp(-r * 4.0) * (0.4 + 0.6 * cos(time * 0.4));

	vec3 col = inner_color.rgb * warm_lobe
		+ vec3(0.10, 0.14, 0.28) * cool_lobe * 0.4
		+ outer_color.rgb;

	// Subtle warm tint shift, no flash.
	col = mix(col, col * vec3(1.05, 1.00, 0.90), warmth);

	// Alpha based on radial falloff so edges stay transparent.
	float a = clamp((warm_lobe + cool_lobe) * 0.55, 0.0, 0.55);

	COLOR = vec4(col, a);
}
