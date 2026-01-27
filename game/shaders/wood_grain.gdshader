shader_type canvas_item;

// Base wood color (set from the ColorRect's color)
uniform vec4 base_color : source_color = vec4(0.22, 0.13, 0.07, 1.0);

// Variation parameters
uniform float variation_scale : hint_range(0.5, 5.0) = 2.0;
uniform float variation_intensity : hint_range(0.0, 0.5) = 0.2;
uniform float seed : hint_range(0.0, 100.0) = 0.0;

// Simple pseudo-random based on position
float hash(float x) {
    return fract(sin(x * 12.9898 + seed) * 43758.5453);
}

// Smooth noise-like function
float noise(float x) {
    float i = floor(x);
    float f = fract(x);
    float a = hash(i);
    float b = hash(i + 1.0);
    // Smooth interpolation
    float u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u);
}

void fragment() {
    // Get normalized X position across the grain line
    float x = UV.x * variation_scale;

    // Generate smooth variation using layered noise
    float n = noise(x) * 0.5 + noise(x * 2.3) * 0.3 + noise(x * 5.1) * 0.2;

    // Center around 0.5 and apply intensity
    float brightness_mod = (n - 0.5) * variation_intensity * 2.0;

    // Apply to base color - darker and lighter regions
    vec3 color = base_color.rgb * (1.0 + brightness_mod);

    COLOR = vec4(color, base_color.a);
}
