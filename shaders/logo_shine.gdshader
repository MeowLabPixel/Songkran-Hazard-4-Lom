shader_type canvas_item;

uniform float Line_Smoothness : hint_range(0, 0.1) = 0.045;
uniform float Line_Width : hint_range(0, 0.2) = 0.09;
uniform float Brightness = 3.0;
uniform float Rotation_deg : hint_range(-90, 90) = 30;
uniform float Distortion : hint_range(1, 2) = 1.8;
uniform float Speed = 0.7;
uniform float Position : hint_range(0, 1) = 0;
uniform float Position_Min = 0.25;
uniform float Position_Max = 0.5;
uniform float Alpha : hint_range(0, 1) = 1;
uniform sampler2D surface: source_color;

vec2 rotate_uv(vec2 uv, vec2 center, float rotation, bool use_degrees){
		float _angle = rotation;
		if(use_degrees){
			_angle = rotation * (3.1415926/180.0);
		}
		mat2 _rotation = mat2(
			vec2(cos(_angle), -sin(_angle)),
			vec2(sin(_angle), cos(_angle))
		);
		vec2 _delta = uv - center;
		_delta = _rotation * _delta;
		return _delta + center;
	}

void fragment() {
	vec2 center_uv = UV - vec2(0.5, 0.5);
	float gradient_to_edge = max(abs(center_uv.x), abs(center_uv.y));
	gradient_to_edge = gradient_to_edge * Distortion;
	gradient_to_edge = 1.0 - gradient_to_edge;
	vec2 rotaded_uv = rotate_uv(UV, vec2(0.5, 0.5), Rotation_deg, true);
	
	float remapped_position;
	{
		float output_range = Position_Max - Position_Min;
		remapped_position = Position_Min + output_range * Position;
	}
	
	// Real-time periodic cycle: 6.0s total duration, 1.8s active sweep
	float real_time = TIME + remapped_position / Speed;
	float time_in_cycle = mod(real_time, 6.0);
	float sweep_val = -2.0;
	if (time_in_cycle < 1.8) {
		sweep_val = -2.0 + 4.0 * (time_in_cycle / 1.8);
	}
	
	vec2 offset_uv = vec2(rotaded_uv.xy) + vec2(sweep_val, 0.0);
	float line = vec3(offset_uv, 0.0).x;
	line = abs(line);
	line = gradient_to_edge * line;
	line = sqrt(line);
	
	float line_smoothness = clamp(Line_Smoothness, 0.001, 1.0);
	float offset_plus = Line_Width + line_smoothness;
	float offset_minus = Line_Width - line_smoothness;
	
	float remapped_line;
	{
		float input_range = offset_minus - offset_plus;
		remapped_line = (line - offset_plus) / input_range;
	}
	remapped_line *= Brightness;
	remapped_line = min(remapped_line, Alpha);
	
	vec4 surface_tex = texture(surface, UV);
	
	// Add the shine sweep on top of the original texture, masked by the logo's alpha
	float shine = max(0.0, remapped_line);
	COLOR.rgb = (surface_tex.rgb + vec3(shine) * surface_tex.a) * Alpha;
	COLOR.a = surface_tex.a * Alpha;
}
