shader_type canvas_item;

uniform float shadow_softness : hint_range(0.0, 1.0) = 0.4;
uniform float shadow_opacity : hint_range(0.0, 1.0) = 0.35;
uniform vec3 shadow_color : source_color = vec3(0.0, 0.0, 0.0);
uniform float blur_radius : hint_range(0.0, 20.0) = 5.0;

void fragment() {
    vec2 uv = UV;
    
    // Get the texture color
    vec4 tex = texture(TEXTURE, uv);
    
    // Create soft edges based on alpha
    float alpha = tex.a;
    
    // Apply softness to the edges
    float soft_alpha = smoothstep(0.0, shadow_softness, alpha);
    
    // Output shadow color with adjusted alpha
    COLOR = vec4(shadow_color, soft_alpha * shadow_opacity);
}
