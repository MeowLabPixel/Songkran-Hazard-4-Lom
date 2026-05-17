shader_type spatial;
render_mode blend_mix,depth_draw_opaque,cull_back,specular_schlick_ggx, diffuse_toon;
// Texturas
uniform sampler2D albedo_texture : source_color;
uniform sampler2D roughness_texture : source_color;

// Dirección de luz
uniform vec3 light_direction = vec3(0.5, 0.0, 0.0);

// Colores por banda de iluminación
uniform vec4 highlight_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 mid1_color : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform vec4 mid2_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.3, 0.3, 0.3, 1.0);

// Umbrales de iluminación
uniform float highlight_threshold : hint_range(0.0, 1.0) = 0.85;
uniform float mid1_threshold : hint_range(0.0, 1.0) = 0.6;
uniform float mid2_threshold : hint_range(0.0, 1.0) = 0.35;

// Suavidad
uniform float smoothness : hint_range(0.0, 1.0) = 0.1;

// Roughness
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform int roughness_channel : hint_range(0, 3) = 0;

void fragment() {
    vec4 tex_color = texture(albedo_texture, UV);
    vec3 normal = normalize(NORMAL);
    vec3 light_dir = normalize(light_direction);
    float NdotL = max(dot(normal, -light_dir), 0.0);


    vec3 toon_color;

    if (smoothness == 0.0) {
        // Transiciones duras
        if (NdotL >= highlight_threshold) {
            toon_color = highlight_color.rgb;
        } else if (NdotL >= mid1_threshold) {
            toon_color = mid1_color.rgb;
        } else if (NdotL >= mid2_threshold) {
            toon_color = mid2_color.rgb;
        } else {
            toon_color = shadow_color.rgb;
        }
    } else {
        // Transiciones suaves con interpolación
        if (NdotL > highlight_threshold) {
            toon_color = highlight_color.rgb;
        } else if (NdotL > mid1_threshold) {
            float t = smoothstep(mid1_threshold - smoothness, highlight_threshold + smoothness, NdotL);
            toon_color = mix(mid1_color.rgb, highlight_color.rgb, t);
        } else if (NdotL > mid2_threshold) {
            float t = smoothstep(mid2_threshold - smoothness, mid1_threshold + smoothness, NdotL);
            toon_color = mix(mid2_color.rgb, mid1_color.rgb, t);
        } else {
            float t = smoothstep(0.0, mid2_threshold + smoothness, NdotL);
            toon_color = mix(shadow_color.rgb, mid2_color.rgb, t);
        }
    }

   ALBEDO = tex_color.rgb * toon_color * 1.5;


    ALPHA = tex_color.a;

    // Roughness con canal seleccionado
    vec4 rough_tex = texture(roughness_texture, UV);
    float raw_roughness = roughness;
    if (roughness_channel == 0) raw_roughness = rough_tex.r * roughness;
    else if (roughness_channel == 1) raw_roughness = rough_tex.g * roughness;
    else if (roughness_channel == 2) raw_roughness = rough_tex.b * roughness;
    else if (roughness_channel == 3) raw_roughness = rough_tex.a * roughness;

    ROUGHNESS = clamp(raw_roughness, 0.2, 0.8);
}
