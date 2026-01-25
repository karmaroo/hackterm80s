shader_type canvas_item;

// CRT Monitor Effect Shader for HackTerm80s
// Creates authentic 80s CRT look with scanlines, curvature, and phosphor glow

// Adjustable parameters
uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.3;
uniform float scanline_frequency : hint_range(100.0, 800.0) = 400.0;
uniform float curvature : hint_range(0.0, 0.5) = 0.1;
uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.4;
uniform float chromatic_aberration : hint_range(0.0, 0.01) = 0.002;
uniform float flicker_intensity : hint_range(0.0, 0.1) = 0.02;
uniform float noise_intensity : hint_range(0.0, 0.2) = 0.05;
uniform float brightness : hint_range(0.5, 2.0) = 1.1;
uniform float contrast : hint_range(0.5, 2.0) = 1.1;
uniform vec3 phosphor_color : source_color = vec3(0.0, 1.0, 0.4); // Green phosphor
uniform bool enable_phosphor_tint = true;
uniform float glow_intensity : hint_range(0.0, 1.0) = 0.15;

// Random function for noise
float random(vec2 st) {
	return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

// Apply barrel distortion for CRT curvature
vec2 curve_uv(vec2 uv) {
	vec2 curved = uv * 2.0 - 1.0;
	vec2 offset = curved.yx * curved.yx * curvature;
	curved += curved * offset;
	return curved * 0.5 + 0.5;
}

void fragment() {
	// Apply screen curvature
	vec2 curved_uv = curve_uv(UV);
	vec3 col = vec3(0.0);
	
	// Check if we're outside the curved screen area
	bool outside = curved_uv.x < 0.0 || curved_uv.x > 1.0 || curved_uv.y < 0.0 || curved_uv.y > 1.0;
	
	if (outside) {
		col = vec3(0.0, 0.0, 0.0);
	} else {
		// Chromatic aberration - separate RGB channels slightly
		float r = texture(TEXTURE, curved_uv + vec2(chromatic_aberration, 0.0)).r;
		float g = texture(TEXTURE, curved_uv).g;
		float b = texture(TEXTURE, curved_uv - vec2(chromatic_aberration, 0.0)).b;
		col = vec3(r, g, b);
		
		// Apply phosphor color tint (green monitor look)
		if (enable_phosphor_tint) {
			float luminance = dot(col, vec3(0.299, 0.587, 0.114));
			col = mix(col, luminance * phosphor_color, 0.7);
		}
		
		// Scanlines
		float scanline = sin(curved_uv.y * scanline_frequency * 3.14159) * 0.5 + 0.5;
		scanline = pow(scanline, 1.5);
		col *= 1.0 - (scanline_intensity * (1.0 - scanline));
		
		// Horizontal sync wobble (subtle)
		float wobble = sin(TIME * 2.0 + curved_uv.y * 10.0) * 0.0005;
		col = mix(col, texture(TEXTURE, curved_uv + vec2(wobble, 0.0)).rgb, 0.3);
		
		// Screen flicker
		float flicker = 1.0 - flicker_intensity * random(vec2(TIME * 0.01, 0.0));
		col *= flicker;
		
		// Static noise
		float noise = random(curved_uv + TIME * 0.1) * noise_intensity;
		col += vec3(noise) * 0.5;
		
		// Vignette effect (darker edges)
		vec2 vignette_uv = curved_uv * (1.0 - curved_uv);
		float vignette = vignette_uv.x * vignette_uv.y * 15.0;
		vignette = pow(vignette, vignette_intensity);
		col *= vignette;
		
		// Brightness and contrast
		col = (col - 0.5) * contrast + 0.5;
		col *= brightness;
		
		// Phosphor glow effect (bloom simulation)
		vec3 glow = texture(TEXTURE, curved_uv).rgb * glow_intensity;
		col += glow * phosphor_color;
		
		// Clamp
		col = clamp(col, 0.0, 1.0);
	}
	
	COLOR = vec4(col, 1.0);
}
