shader_type canvas_item;

// Invalid dim shader — fade/dim effect on invalid permutation attempt
// Desaturates and darkens the visual, with a subtle red tint

uniform float dim_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 error_tint : source_color = vec4(0.8, 0.2, 0.2, 1.0);
uniform float shake_intensity : hint_range(0.0, 10.0) = 0.0;
uniform float shake_speed : hint_range(0.0, 30.0) = 15.0;

void fragment() {
    // UV offset for shake effect
    vec2 uv = UV;
    if (shake_intensity > 0.0) {
        uv.x += sin(TIME * shake_speed) * shake_intensity * 0.005;
        uv.y += cos(TIME * shake_speed * 1.3) * shake_intensity * 0.003;
    }

    vec4 tex_color = texture(TEXTURE, uv);

    // Desaturation
    float gray = dot(tex_color.rgb, vec3(0.299, 0.587, 0.114));
    vec3 desaturated = mix(tex_color.rgb, vec3(gray), dim_amount);

    // Darken
    vec3 dimmed = desaturated * (1.0 - dim_amount * 0.5);

    // Error tint
    vec3 tinted = mix(dimmed, error_tint.rgb * gray, dim_amount * 0.3);

    COLOR = vec4(tinted, tex_color.a);
}
