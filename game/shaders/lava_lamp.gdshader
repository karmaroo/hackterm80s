shader_type canvas_item;

// Control uniforms
uniform bool is_on = true;
uniform float blob_speed : hint_range(0.05, 0.5) = 0.15;
uniform float blob_threshold : hint_range(0.5, 2.0) = 1.0;
uniform float temperature : hint_range(0.0, 1.0) = 1.0; // 0 = cold, 1 = hot

// Color uniforms
uniform vec4 liquid_color : source_color = vec4(0.02, 0.04, 0.03, 1.0);
uniform vec4 blob_color_bottom : source_color = vec4(0.2, 0.9, 0.4, 1.0);
uniform vec4 blob_color_top : source_color = vec4(0.3, 0.95, 0.85, 1.0);

// Chrome colors - dark gunmetal
uniform vec4 chrome_light : source_color = vec4(0.35, 0.35, 0.38, 1.0);
uniform vec4 chrome_mid : source_color = vec4(0.2, 0.2, 0.22, 1.0);
uniform vec4 chrome_dark : source_color = vec4(0.08, 0.08, 0.1, 1.0);

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Get lamp width at any Y position - returns width and region type
// region: 0 = outside, 1 = glass, 2 = chrome
vec2 get_lamp_shape(float y) {
    float top_width = 0.22;
    
    // Top cap (flat/slight dome) - 0% to 6%
    if (y < 0.06) {
        float t = y / 0.06;
        float width = mix(0.12, top_width, sqrt(t));
        return vec2(width, 2.0);
    }
    
    // Neck ring - thin chrome band - 6% to 10%
    if (y < 0.10) {
        return vec2(top_width, 2.0);
    }
    
    // Glass body - smooth continuous curve - 10% to 80%
    if (y < 0.80) {
        float t = (y - 0.10) / 0.70;
        
        // Wider middle bulge and wider bottom
        float max_width = 0.38;
        float bottom_width = 0.28;
        
        // Use smooth sine curve for the bulge
        float bulge = sin(t * 3.14159);
        float taper = smoothstep(0.0, 1.0, t);
        
        // Blend: start at top_width, bulge out more, then taper
        float base_width = mix(top_width, bottom_width, taper);
        float width = base_width + bulge * (max_width - top_width) * 0.7;
        
        return vec2(width, 1.0);
    }
    
    // Base collar (chrome ring) - 80% to 83%
    if (y < 0.83) {
        return vec2(0.28, 2.0);  // Match body bottom width exactly
    }
    
    // Base body - tapers out smoothly - 83% to 100%
    if (y <= 1.0) {
        float t = (y - 0.83) / 0.17;
        // Start at body width, taper outward to wider base
        float width = mix(0.28, 0.34, smoothstep(0.0, 1.0, t));
        return vec2(width, 2.0);
    }
    
    return vec2(0.0, 0.0);
}

// Classic lava lamp shape with anti-aliased edges
// Returns: x = signed distance (negative inside), y = region (1=glass, 2=chrome)
vec2 get_lamp_sdf(vec2 uv) {
    float x = uv.x;
    float y = uv.y;
    float cx = 0.5;
    
    vec2 shape = get_lamp_shape(y);
    float width = shape.x;
    float region = shape.y;
    
    // Signed distance from edge (negative = inside)
    float dist = abs(x - cx) - width;
    
    return vec2(dist, region);
}

// Get glass width at a y position (for blob containment)
float get_glass_width(float y) {
    if (y < 0.12 || y > 0.78) {
        return 0.0;
    }
    
    float t = (y - 0.12) / 0.66;
    
    // Match the smooth body shape - wider middle and bottom
    float top_width = 0.20;
    float max_width = 0.36;
    float bottom_width = 0.26;
    
    float bulge = sin(t * 3.14159);
    float taper = smoothstep(0.0, 1.0, t);
    float base_width = mix(top_width, bottom_width, taper);
    
    return base_width + bulge * (max_width - top_width) * 0.65;
}

// Chrome gradient shading
vec4 get_chrome_color(vec2 uv) {
    float x = uv.x;
    float y_wave = 0.7 + 0.3 * sin(uv.y * 8.0);
    
    // Horizontal gradient for 3D effect
    if (x < 0.35) {
        return mix(chrome_dark, chrome_mid, (x / 0.35) * y_wave);
    } else if (x < 0.55) {
        float center_t = abs(x - 0.45) / 0.1;
        return mix(chrome_light, chrome_mid, center_t * y_wave);
    } else {
        return mix(chrome_mid, chrome_dark, ((x - 0.55) / 0.45) * y_wave);
    }
}

// Smooth blob oscillation
float oscillate(float t, float offset, float speed) {
    return pow(sin(t * speed + offset), 2.0);
}

void fragment() {
    vec2 uv = UV;
    
    // Get SDF and region
    vec2 sdf_result = get_lamp_sdf(uv);
    float dist = sdf_result.x;
    float region = sdf_result.y;
    
    // Anti-aliasing: smooth edge over ~2 pixels
    float aa_width = 0.008;
    float edge_alpha = 1.0 - smoothstep(-aa_width, aa_width, dist);
    
    // Outside lamp - transparent
    if (edge_alpha < 0.01) {
        COLOR = vec4(0.0, 0.0, 0.0, 0.0);
    } else if (region > 1.5) {
        // Chrome base/cap
        vec4 chrome = get_chrome_color(uv);
        chrome.a *= edge_alpha;
        COLOR = chrome;
    } else {
        // Glass area - lava effect
        vec4 final_color;

        float glass_top = 0.14;
        float glass_bottom = 0.78;

        // Use temperature for all blob behavior (allows cooling animation)
        // When completely cold AND off, show static single blob
        if (temperature < 0.02 && !is_on) {
            // Single large blob sitting at the bottom - completely cold
            float blob_y = glass_bottom - 0.06;
            float blob_x = 0.50;
            float blob_r = 0.10;  // Large blob radius

            vec2 p = uv - vec2(blob_x, blob_y);
            p.y *= 0.35;  // Flatten it like a puddle
            float d = length(p);
            float influence = blob_r / (d + 0.01);

            float thresh = 0.9;
            float grad = clamp((uv.y - glass_top) / (glass_bottom - glass_top), 0.0, 1.0);
            vec4 blob_col = mix(blob_color_bottom, blob_color_top, grad) * 0.25;  // Very dim when cold
            vec4 liquid_col = liquid_color * 0.2;

            if (influence > thresh) {
                final_color = blob_col;
            } else if (influence > thresh * 0.5) {
                float edge = (influence - thresh * 0.5) / (thresh * 0.5);
                final_color = mix(liquid_col, blob_col, smoothstep(0.0, 1.0, edge));
            } else {
                final_color = liquid_col;
            }
        } else {
            // Animated metaball blobs affected by temperature
            // Cold: 1 large blob at bottom, blobs merge
            // Hot: 4-5 smaller blobs moving around freely

            float influence = 0.0;

            // Animation time
            float anim = TIME * 0.1;

            // 4 blobs with temperature-dependent behavior
            // When cold: large radii, low threshold = merge into one
            // When hot: small radii, high threshold = separate blobs

            // Blob radii - MUCH smaller when hot to allow separation
            float r0 = mix(0.015, 0.004, temperature);  // Big -> small
            float r1 = mix(0.012, 0.003, temperature);
            float r2 = mix(0.010, 0.0025, temperature);
            float r3 = mix(0.011, 0.003, temperature);

            // Y positions - full oscillation when hot, sink to bottom when cold
            float y_range = mix(0.15, 1.0, temperature);
            float y_offset = mix(0.12, 0.0, temperature);  // Shift down when cold

            float y0 = glass_top + 0.04 + y_offset + pow(sin(anim * 0.6), 2.0) * (glass_bottom - glass_top - 0.08) * y_range;
            float y1 = glass_top + 0.04 + y_offset + pow(sin(anim * 0.45 + 2.1), 2.0) * (glass_bottom - glass_top - 0.08) * y_range;
            float y2 = glass_top + 0.04 + y_offset + pow(sin(anim * 0.75 + 4.2), 2.0) * (glass_bottom - glass_top - 0.08) * y_range;
            float y3 = glass_top + 0.04 + y_offset + pow(sin(anim * 0.55 + 1.0), 2.0) * (glass_bottom - glass_top - 0.08) * y_range;

            // X positions - more spread when hot, clustered when cold
            float x_spread = mix(0.01, 0.07, temperature);
            float x0 = 0.50 + x_spread * sin(anim * 0.5);
            float x1 = 0.50 + x_spread * sin(anim * 0.4 + 1.5);
            float x2 = 0.50 + x_spread * sin(anim * 0.6 + 3.0);
            float x3 = 0.50 + x_spread * sin(anim * 0.45 + 4.5);

            // Metaball influence calculation
            vec2 p0 = uv - vec2(x0, y0);
            vec2 p1 = uv - vec2(x1, y1);
            vec2 p2 = uv - vec2(x2, y2);
            vec2 p3 = uv - vec2(x3, y3);

            // Vertical stretch - flatter when cold
            float y_stretch = mix(0.4, 0.7, temperature);
            p0.y *= y_stretch;
            p1.y *= y_stretch;
            p2.y *= y_stretch;
            p3.y *= y_stretch;

            float d0 = dot(p0, p0) + 0.0001;
            float d1 = dot(p1, p1) + 0.0001;
            float d2 = dot(p2, p2) + 0.0001;
            float d3 = dot(p3, p3) + 0.0001;

            influence = r0/d0 + r1/d1 + r2/d2 + r3/d3;

            // Threshold - LOW when cold (blobs merge), HIGH when hot (blobs separate)
            // This is the KEY to separation!
            float dynamic_threshold = mix(0.7, 2.8, temperature);

            // Color based on metaball influence
            // Brightness affected by temperature - dimmer when cooling
            float brightness = mix(0.3, 1.0, temperature);
            vec4 liquid_col = liquid_color * mix(0.25, 1.0, temperature);

            if (influence > dynamic_threshold) {
                float grad = (uv.y - glass_top) / (glass_bottom - glass_top);
                final_color = mix(blob_color_bottom, blob_color_top, clamp(grad, 0.0, 1.0));
                final_color.rgb *= brightness;
                // Slight glow at edges
                float glow = (influence - dynamic_threshold) / dynamic_threshold;
                final_color.rgb *= 1.0 + glow * 0.12 * temperature;
            } else if (influence > dynamic_threshold * 0.5) {
                float edge = (influence - dynamic_threshold * 0.5) / (dynamic_threshold * 0.5);
                edge = smoothstep(0.0, 1.0, edge);
                float grad = (uv.y - glass_top) / (glass_bottom - glass_top);
                vec4 blob_col = mix(blob_color_bottom, blob_color_top, clamp(grad, 0.0, 1.0));
                blob_col.rgb *= brightness;
                final_color = mix(liquid_col, blob_col, edge);
            } else {
                final_color = liquid_col;
            }
        }
        
        // Glass reflection highlight on left edge
        float glass_w = get_glass_width(uv.y);
        if (glass_w > 0.0) {
            float edge_dist_left = (uv.x - (0.5 - glass_w)) / (glass_w * 2.0);
            if (edge_dist_left < 0.15) {
                float highlight = (0.15 - edge_dist_left) / 0.15;
                highlight = pow(highlight, 2.0) * 0.2;
                final_color.rgb += vec3(highlight);
            }
        }
        
        // Apply anti-aliased edge
        final_color.a *= edge_alpha;
        COLOR = final_color;
    }
}
