shader_type canvas_item;

// Valid flash shader — shimmer/flash effect when player discovers a valid symmetry
// Applied to entire level or individual crystals on successful automorphism

uniform vec4 flash_color : source_color = vec4(1.0, 0.95, 0.6, 1.0);
uniform float flash_intensity : hint_range(0.0, 5.0) = 0.0;
uniform float shimmer_speed : hint_range(0.0, 10.0) = 3.0;
uniform float shimmer_scale : hint_range(1.0, 50.0) = 15.0;
uniform float wave_speed : hint_range(0.0, 10.0) = 4.0;

void fragment() {
    vec4 tex_color = texture(TEXTURE, UV);

    // Radial shimmer wave from center
    vec2 center = vec2(0.5, 0.5);
    float dist = distance(UV, center);

    // Shimmer pattern — multi-frequency sparkle
    float shimmer = sin(UV.x * shimmer_scale + TIME * shimmer_speed)
                  * cos(UV.y * shimmer_scale * 0.7 - TIME * shimmer_speed * 0.8);
    shimmer = shimmer * 0.5 + 0.5; // Normalize to 0..1

    // Radial wave expanding outward
    float wave = sin(dist * 20.0 - TIME * wave_speed);
    wave = max(0.0, wave);

    // Combined flash effect (controlled by flash_intensity, animated externally)
    float effect = flash_intensity * (shimmer * 0.4 + wave * 0.6);

    // Additive blend with flash color
    vec4 result = tex_color;
    result.rgb += flash_color.rgb * effect;
    result.rgb = min(result.rgb, vec3(1.5)); // Allow slight HDR bloom feel

    COLOR = result;
}
