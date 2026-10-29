shader_type canvas_item;

#define iResolution (1.0 / SCREEN_PIXEL_SIZE)
#define iTime TIME
#define fragColor COLOR

uniform float uv_scale : hint_range(0.0, 10.0, 0.1) = 1.2;
uniform float color_alpha : hint_range(0.0, 1.0, 0.05) = 0.85;

uniform vec4 water_colour : source_color = vec4(0.06, 0.12, 0.32, 1.0);
uniform vec4 sky_colour : source_color = vec4(0.12, 0.62, 0.82, 1.0);
uniform vec4 foam_colour : source_color = vec4(0.8, 0.95, 1.0, 1.0);
uniform vec4 specular_colour : source_color = vec4(1.0, 1.0, 1.0, 1.0);

vec2 hash(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float noise(in vec2 p) {
	const float K1 = 0.366025404; // (sqrt(3)-1)/2;
	const float K2 = 0.211324865; // (3-sqrt(3))/6;

	vec2 i = floor(p + (p.x + p.y) * K1);
	vec2 a = p - i + (i.x + i.y) * K2;
	float m = step(a.y, a.x);
	vec2 o = vec2(m, 1.0 - m);
	vec2 b = a - o + K2;
	vec2 c = a - 1.0 + 2.0 * K2;
	vec3 h = max(0.5 - vec3(dot(a, a), dot(b, b), dot(c, c)), 0.0);
	vec3 n = h * h * h * h * vec3(dot(a, hash(i + 0.0)), dot(b, hash(i + o)), dot(c, hash(i + 1.0)));
	return dot(n, vec3(70.0));
}

#define MAX_WAVES 4
#define SUPERPOSITION 4
#define TAU 6.28318530718
#define PHI 1.61803398875

float height(vec2 p, float t) {
	float acc = 0.0;
	for (int i = 0; i < MAX_WAVES; i++) {
		for (int j = 0; j < SUPERPOSITION; j++) {
			int seed = i + 5 * j;
			float theta = TAU * PHI * 10.0 * float(seed);
			float up = cos(theta) * p.x - sin(theta) * p.y;
			float vp = sin(theta) * p.x + cos(theta) * p.y;
			float initial_phase = TAU * PHI * float(seed);
			float k = pow(2.0, float(i));
			float phase = initial_phase + up * k + cos(vp) + 2.5 * t + 0.4 * k * t;
			float A = cos(phase) / (k * k);
			acc += A;
		}
	}
	return acc;
}

vec4 hn_fdm(vec2 p, float t) {
	float h = height(p, t);
	vec2 vx = vec2(0.1, 0.0);
	vec2 vy = vec2(0.0, 0.1);
	float hx = height(p + vx, t);
	float hy = height(p + vy, t);
	float dx = (hx - h);
	float dy = (hy - h);

	vec3 v1 = normalize(vec3(vx.x, 0.0, dx));
	vec3 v2 = normalize(vec3(0.0, vy.y, dy));
	vec3 norm = cross(v1, v2);

	return vec4(norm, h);
}

void fragment() {
	vec2 uv = UV;
	vec2 uv_screen = (uv - 0.5) * uv_scale;

	vec4 nh = hn_fdm(uv_screen * 10.0, iTime * 0.8);
	float h = nh.w;
	vec3 norm = nh.xyz;
	vec3 sun_dir = normalize(vec3(-0.2, 0.4, 1.0));

	if (dot(sun_dir, norm) > 0.98) {
		fragColor = specular_colour;
	} else {
		fragColor = mix(water_colour, sky_colour, clamp(dot(norm, normalize(vec3(0.0, 0.2, 1.0))), 0.0, 1.0));
	}
	fragColor.a = color_alpha;
}
