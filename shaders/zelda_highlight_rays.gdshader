shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

uniform vec4 beam_color : source_color = vec4(1.0, 0.9, 0.4, 1.0);
uniform float vertical_speed : hint_range(0.0, 5.0) = 0.5;
uniform bool reverse_direction = false;
uniform float rotation_speed : hint_range(0.0, 2.0) = 0.1;
uniform float density : hint_range(1.0, 50.0) = 20.0;
uniform float ray_sharpness : hint_range(0.0, 1.0) = 0.45;
uniform bool fade_towards_top = true;
uniform float fade_power : hint_range(0.5, 4.0) = 1.5;
uniform sampler2D noise_texture : repeat_enable;

void fragment() {
	vec2 scrolling_uv = UV;
	if (reverse_direction) {
		scrolling_uv.y -= TIME * vertical_speed;
	} else {
		scrolling_uv.y += TIME * vertical_speed;
	}

	if (rotation_speed != 0.0) {
		scrolling_uv.x += TIME * rotation_speed;
	}

	vec2 noise_uv = scrolling_uv;
	noise_uv.x *= density;
	noise_uv.y *= 0.1;

	float noise_value = texture(noise_texture, noise_uv).r;
	float rays = smoothstep(ray_sharpness, ray_sharpness + 0.15, noise_value);

	// In Godot CylinderMesh, UV.y = 0 at top and 1 at bottom
	float vertical_fade = fade_towards_top ? UV.y : (1.0 - UV.y);
	vertical_fade = pow(clamp(vertical_fade, 0.0, 1.0), fade_power);

	ALBEDO = beam_color.rgb;
	ALPHA = rays * vertical_fade * beam_color.a;
	EMISSION = beam_color.rgb;
}
