shader_type canvas_item;

uniform vec3 wood_color_light : source_color = vec3(0.55, 0.35, 0.2);
uniform vec3 wood_color_dark : source_color = vec3(0.38, 0.22, 0.12);
uniform float grain_scale : hint_range(1.0, 50.0) = 15.0;
uniform float grain_intensity : hint_range(0.0, 1.0) = 0.3;
uniform float highlight_strength : hint_range(0.0, 1.0) = 0.15;
uniform vec2 light_position = vec2(0.5, 0.0);
uniform vec3 monitor_glow_color : source_color = vec3(0.15, 0.35, 0.2);
uniform float monitor_glow_strength : hint_range(0.0, 1.0) = 0.12;
uniform vec2 monitor_glow_pos = vec2(0.5, 0.0);

// Noise functions for wood grain
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Fractal noise for more natural wood
float fbm(vec2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 4; i++) {
        value += amplitude * noise(p);
        p *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

void fragment() {
    vec2 uv = UV;
    
    // Create wood grain pattern (horizontal streaks)
    vec2 grain_uv = uv * vec2(grain_scale * 0.3, grain_scale);
    float grain = fbm(grain_uv + vec2(0.0, uv.x * 5.0));
    
    // Add some variation
    float variation = noise(uv * grain_scale * 2.0) * 0.3;
    grain = grain + variation;
    
    // Mix wood colors based on grain
    vec3 wood = mix(wood_color_dark, wood_color_light, grain * grain_intensity + (1.0 - grain_intensity) * 0.5);
    
    // Add subtle horizontal grain lines
    float fine_grain = sin(uv.y * grain_scale * 20.0 + noise(uv * 50.0) * 3.0) * 0.5 + 0.5;
    fine_grain = smoothstep(0.3, 0.7, fine_grain);
    wood = mix(wood, wood * 0.92, fine_grain * 0.15);
    
    // Lighting - highlight from above
    float light_dist = length((uv - light_position) * vec2(1.0, 2.0));
    float highlight = 1.0 - smoothstep(0.0, 0.8, light_dist);
    highlight = pow(highlight, 2.0);
    wood += vec3(highlight * highlight_strength);
    
    // Edge darkening (subtle vignette on desk)
    float edge_dark = smoothstep(0.0, 0.15, uv.x) * smoothstep(0.0, 0.15, 1.0 - uv.x);
    wood *= 0.85 + edge_dark * 0.15;
    
    // Front edge highlight (desk front catches light)
    float front_highlight = smoothstep(0.7, 1.0, uv.y) * 0.08;
    wood += vec3(front_highlight);
    
    // Monitor glow reflection on desk
    float glow_dist = length((uv - monitor_glow_pos) * vec2(1.0, 3.0));
    float glow = 1.0 - smoothstep(0.0, 0.5, glow_dist);
    glow = pow(glow, 2.5);
    wood += monitor_glow_color * glow * monitor_glow_strength;
    
    // Subtle depth gradient (back darker than front)
    wood *= 0.9 + uv.y * 0.1;
    
    COLOR = vec4(wood, 1.0);
}
