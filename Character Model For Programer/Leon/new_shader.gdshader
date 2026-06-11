shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// Texturas
uniform sampler2D albedo_texture : source_color;
uniform sampler2D roughness_texture : source_color;

// Luz
uniform vec3 light_direction = vec3(0.5, 0.0, 0.0);

// Roughness
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform int roughness_channel : hint_range(0, 3) = 0;

// Colores
uniform vec3 base_color : source_color = vec3(1.0);
uniform vec3 highlight_color : source_color = vec3(1.0);
uniform vec3 shadow_color : source_color = vec3(0.0);

// Parámetros de patrón
uniform float dot_pattern_scale : hint_range(1.0, 100.0) = 25.0; // Tamaño de los puntos
uniform float dot_density : hint_range(1.0, 100.0) = 10.0;       // Cuántos puntos hay
uniform float angle : hint_range(0.0, 6.2831) = 0.0;
uniform float shape_smooth : hint_range(0.0, 1.0) = 0.05;

// Rango de luz/sombra
uniform float highlight_range : hint_range(0.0, 1.0) = 0.7;
uniform float shadow_range : hint_range(0.0, 1.0) = 0.3;

void fragment() {
    vec4 tex_color = texture(albedo_texture, UV);
    vec3 normal = normalize(NORMAL);
    vec3 light_dir = normalize(light_direction);
    float NdotL = clamp(dot(normal, -light_dir), 0.0, 1.0);

    // Rotar UV
    mat2 rotation = mat2(
        vec2(cos(angle), -sin(angle)),
        vec2(sin(angle),  cos(angle))
    );
    vec2 rotated_uv = rotation * UV;

    float pattern_value = 0.0;
    vec3 result_color = base_color;

    // Densidad final
    float final_pattern_scale = dot_pattern_scale * dot_density;

    if (NdotL >= highlight_range) {
        vec2 grid_uv = rotated_uv * final_pattern_scale;
        vec2 cell = fract(grid_uv) - 0.5;
        float dist = length(cell);
        float radius = (1.0 - NdotL) * 0.5;
        pattern_value = smoothstep(radius, radius - shape_smooth, dist);
        result_color = mix(highlight_color, base_color, pattern_value);
    } else if (NdotL <= shadow_range) {
        vec2 grid_uv = rotated_uv * final_pattern_scale;
        vec2 cell = fract(grid_uv) - 0.5;
        float dist = length(cell);
        float radius = NdotL * 0.5;
        pattern_value = smoothstep(radius, radius - shape_smooth, dist);
        result_color = mix(base_color, shadow_color, pattern_value);
    }

    ALBEDO = tex_color.rgb * result_color;
    ALPHA = tex_color.a;

    // Roughness con canal
    vec4 rough_tex = texture(roughness_texture, UV);
    float raw_roughness = roughness;
    if (roughness_channel == 0) raw_roughness = rough_tex.r * roughness;
    else if (roughness_channel == 1) raw_roughness = rough_tex.g * roughness;
    else if (roughness_channel == 2) raw_roughness = rough_tex.b * roughness;
    else if (roughness_channel == 3) raw_roughness = rough_tex.a * roughness;

    ROUGHNESS = clamp(raw_roughness, 0.2, 0.8);
}
