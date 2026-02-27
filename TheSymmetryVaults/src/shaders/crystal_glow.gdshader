shader_type canvas_item;

// Crystal glow shader — pulsing radial glow around crystal nodes
// Used by CrystalNode to create the ambient glow effect

uniform vec4 glow_color : source_color = vec4(0.4, 0.7, 1.0, 1.0);
uniform float glow_intensity : hint_range(0.0, 3.0) = 1.0;
uniform float glow_radius : hint_range(0.0, 1.0) = 0.4;
uniform float pulse_speed : hint_range(0.0, 5.0) = 1.5;
uniform float pulse_amplitude : hint_range(0.0, 0.5) = 0.15;
uniform float time_offset : hint_range(0.0, 6.28) = 0.0;

void fragment() {
    vec4 tex_color = texture(TEXTURE, UV);

    // Distance from center for radial glow
    vec2 center = vec2(0.5, 0.5);
    float dist = distance(UV, center);

    // Pulsing effect
    float pulse = 1.0 + pulse_amplitude * sin(TIME * pulse_speed + time_offset);

    // Radial glow falloff
    float glow_factor = smoothstep(glow_radius * pulse, 0.0, dist);
    glow_factor *= glow_intensity;

    // Combine original texture with glow
    vec4 glow = glow_color * glow_factor;
    COLOR = tex_color + glow * tex_color.a;
    COLOR.a = tex_color.a + glow_factor * 0.3;
}
