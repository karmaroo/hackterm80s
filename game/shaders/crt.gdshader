shader_type canvas_item;

// CRT Monitor Effect Shader for HackTerm80s
// Authentic green phosphor CRT with realistic glow

// Screen effects
uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.15;
uniform float scanline_frequency : hint_range(100.0, 800.0) = 400.0;
uniform float chromatic_aberration : hint_range(0.0, 0.01) = 0.0005;
uniform float flicker_intensity : hint_range(0.0, 0.1) = 0.005;
uniform float noise_intensity : hint_range(0.0, 0.2) = 0.02;

// Display settings
uniform float brightness : hint_range(0.5, 3.0) = 1.5;
uniform float contrast : hint_range(0.5, 2.0) = 1.15;

// Phosphor/CRT color
uniform vec3 phosphor_color : source_color = vec3(0.2, 1.0, 0.5);
uniform float phosphor_tint_strength : hint_range(0.0, 1.0) = 0.8;

// CRT background glow (green tint when monitor is on)
uniform vec3 screen_base_color : source_color = vec3(0.0, 0.12, 0.06);
uniform float screen_base_strength : hint_range(0.0, 1.0) = 1.0;

// Bloom/glow around bright content
uniform float glow_intensity : hint_range(0.0, 1.0) = 0.2;
uniform float glow_radius : hint_range(1.0, 10.0) = 3.0;

// Random function for noise
float random(vec2 st) {
	return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

// Simple blur for glow effect
vec3 blur_sample(sampler2D tex, vec2 uv, vec2 pixel_size) {
	vec3 col = vec3(0.0);
	float total = 0.0;

	for (float x = -2.0; x <= 2.0; x += 1.0) {
		for (float y = -2.0; y <= 2.0; y += 1.0) {
			float weight = 1.0 - length(vec2(x, y)) / 3.5;
			weight = max(weight, 0.0);
			col += texture(tex, uv + vec2(x, y) * pixel_size * glow_radius).rgb * weight;
			total += weight;
		}
	}
	return col / total;
}

void fragment() {
	vec2 pixel_size = 1.0 / vec2(textureSize(TEXTURE, 0));

	// Start with the green-tinted CRT base color (phosphor glow when monitor is on)
	vec3 col = screen_base_color * screen_base_strength;

	// Sample the texture with chromatic aberration
	float r = texture(TEXTURE, UV + vec2(chromatic_aberration, 0.0)).r;
	float g = texture(TEXTURE, UV).g;
	float b = texture(TEXTURE, UV - vec2(chromatic_aberration, 0.0)).b;
	vec3 text_color = vec3(r, g, b);

	// Convert to luminance and apply phosphor color tint
	float luminance = dot(text_color, vec3(0.299, 0.587, 0.114));
	vec3 tinted = luminance * phosphor_color;
	text_color = mix(text_color, tinted, phosphor_tint_strength);

	// Apply brightness to text
	text_color *= brightness;

	// Add bloom/glow around bright areas
	vec3 glow = blur_sample(TEXTURE, UV, pixel_size);
	float glow_luminance = dot(glow, vec3(0.299, 0.587, 0.114));
	vec3 glow_colored = glow_luminance * phosphor_color * glow_intensity;

	// Combine: base green + text + glow
	col += text_color + glow_colored;

	// Scanlines
	float scanline = sin(UV.y * scanline_frequency * 3.14159) * 0.5 + 0.5;
	scanline = pow(scanline, 1.2);
	col *= 1.0 - (scanline_intensity * (1.0 - scanline));

	// Screen flicker (subtle)
	float flicker = 1.0 - flicker_intensity * random(vec2(floor(TIME * 30.0), 0.0));
	col *= flicker;

	// Static noise (very subtle)
	float noise = random(UV * 500.0 + TIME) * noise_intensity;
	col += vec3(noise * 0.3, noise, noise * 0.5);

	// Apply contrast
	col = (col - 0.5) * contrast + 0.5;

	// Clamp final output
	col = clamp(col, 0.0, 1.0);

	COLOR = vec4(col, 1.0);
}
