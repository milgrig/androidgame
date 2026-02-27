shader_type canvas_item;

// Edge glow shader — glow effect along edges connecting crystals
// Supports different visual styles: standard, thick, glowing, dashed

uniform vec4 edge_color : source_color = vec4(0.5, 0.6, 0.8, 0.7);
uniform float glow_width : hint_range(0.0, 1.0) = 0.3;
uniform float glow_intensity : hint_range(0.0, 3.0) = 0.8;
uniform float flow_speed : hint_range(0.0, 5.0) = 0.5;
uniform float flow_intensity : hint_range(0.0, 1.0) = 0.2;
uniform bool is_thick = false;
uniform bool is_glowing = false;
uniform bool is_dashed = false;
uniform float dash_length : hint_range(0.01, 0.5) = 0.1;

void fragment() {
    vec4 tex_color = texture(TEXTURE, UV);

    // Core edge visibility based on UV.y distance from center (0.5)
    float center_dist = abs(UV.y - 0.5);
    float edge_width = is_thick ? 0.35 : 0.15;
    float edge_alpha = smoothstep(edge_width, edge_width * 0.5, center_dist);

    // Glow around the edge
    float glow_alpha = smoothstep(glow_width, 0.0, center_dist) * glow_intensity;
    if (is_glowing) {
        glow_alpha *= 1.5;
    }

    // Flowing energy effect along the edge
    float flow = sin(UV.x * 20.0 - TIME * flow_speed) * flow_intensity;
    float energy = edge_alpha + flow * edge_alpha;

    // Dashed pattern
    float dash_mask = 1.0;
    if (is_dashed) {
        dash_mask = step(0.5, fract(UV.x / dash_length));
    }

    // Final color
    vec4 final_color = edge_color;
    final_color.a = (edge_alpha + glow_alpha * 0.5) * dash_mask;
    final_color.rgb += vec3(flow * 0.3) * edge_alpha;

    // Add extra glow for glowing type
    if (is_glowing) {
        float pulse = 0.8 + 0.2 * sin(TIME * 2.0);
        final_color.rgb *= pulse;
        final_color.a *= pulse;
    }

    COLOR = final_color;
}
