shader_type canvas_item;

uniform vec3 color_top : source_color = vec3(0.04, 0.035, 0.07);
uniform vec3 color_mid : source_color = vec3(0.09, 0.075, 0.13);
uniform vec3 color_bottom : source_color = vec3(0.14, 0.11, 0.18);
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.45;
uniform float vignette_softness : hint_range(0.1, 2.0) = 0.8;
uniform vec3 monitor_glow_color : source_color = vec3(0.1, 0.25, 0.15);
uniform float monitor_glow_strength : hint_range(0.0, 1.0) = 0.2;
uniform vec2 monitor_glow_center = vec2(0.5, 0.35);
uniform float monitor_glow_radius : hint_range(0.1, 1.0) = 0.4;
uniform vec3 ceiling_light_color : source_color = vec3(0.25, 0.2, 0.15);
uniform float ceiling_light_strength : hint_range(0.0, 1.0) = 0.08;
uniform float noise_strength : hint_range(0.0, 0.1) = 0.015;

// Simple noise function
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

void fragment() {
    vec2 uv = UV;
    
    // Smooth vertical gradient (top to bottom)
    float gradient_pos = uv.y;
    vec3 wall_color;
    if (gradient_pos < 0.5) {
        wall_color = mix(color_top, color_mid, gradient_pos * 2.0);
    } else {
        wall_color = mix(color_mid, color_bottom, (gradient_pos - 0.5) * 2.0);
    }
    
    // Add ceiling light (warm glow from top center)
    float ceiling_dist = length(vec2(uv.x - 0.5, uv.y * 2.0));
    float ceiling_glow = 1.0 - smoothstep(0.0, 0.8, ceiling_dist);
    wall_color += ceiling_light_color * ceiling_glow * ceiling_light_strength;
    
    // Add monitor glow (green tint emanating from monitor area)
    float monitor_dist = length((uv - monitor_glow_center) * vec2(1.0, 1.5));
    float monitor_glow = 1.0 - smoothstep(0.0, monitor_glow_radius, monitor_dist);
    monitor_glow = pow(monitor_glow, 1.5); // Softer falloff
    wall_color += monitor_glow_color * monitor_glow * monitor_glow_strength;
    
    // Vignette effect (darkening at edges)
    vec2 vignette_uv = uv * 2.0 - 1.0;
    float vignette_dist = length(vignette_uv * vec2(0.8, 1.0));
    float vignette = 1.0 - smoothstep(vignette_softness, vignette_softness + 0.5, vignette_dist);
    vignette = mix(1.0 - vignette_strength, 1.0, vignette);
    wall_color *= vignette;
    
    // Corner darkening (extra dark in corners)
    float corner_dist = length(vignette_uv);
    float corner_dark = smoothstep(1.0, 1.8, corner_dist);
    wall_color *= 1.0 - corner_dark * 0.3;
    
    // Subtle noise for texture
    float n = noise(uv * 200.0) * noise_strength;
    wall_color += vec3(n) - noise_strength * 0.5;
    
    COLOR = vec4(wall_color, 1.0);
}
