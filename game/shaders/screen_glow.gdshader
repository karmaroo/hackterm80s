shader_type canvas_item;

// Phosphor glow effect for CRT monitor
uniform float glow_radius : hint_range(0.0, 10.0) = 2.0;
uniform float glow_intensity : hint_range(0.0, 2.0) = 0.5;
uniform vec3 glow_color : source_color = vec3(0.0, 1.0, 0.4);

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	
	// Simple bloom by sampling nearby pixels
	vec2 pixel_size = 1.0 / vec2(textureSize(TEXTURE, 0));
	vec4 bloom = vec4(0.0);
	
	for (float x = -glow_radius; x <= glow_radius; x += 1.0) {
		for (float y = -glow_radius; y <= glow_radius; y += 1.0) {
			vec2 offset = vec2(x, y) * pixel_size;
			bloom += texture(TEXTURE, UV + offset);
		}
	}
	
	float samples = (glow_radius * 2.0 + 1.0) * (glow_radius * 2.0 + 1.0);
	bloom /= samples;
	
	// Apply glow
	vec3 final_color = tex_color.rgb + bloom.rgb * glow_intensity * glow_color;
	COLOR = vec4(final_color, tex_color.a);
}
