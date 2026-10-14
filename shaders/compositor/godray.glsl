#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Binding 0: Destination color image (read & write, additive blend)
layout(rgba16f, set = 0, binding = 0) uniform image2D color_image;

// Binding 1: Depth texture
layout(set = 0, binding = 1) uniform sampler2D depth_tex;

// Binding 2: Uniform Buffer Object (UBO std140 layout, completely immune to push constant limits)
layout(set = 0, binding = 2, std140) uniform GodrayParams {
    vec4 light_and_facing;      // xy: light_screen_pos, z: sun_facing, w: time_val
    vec4 ray_params;            // x: num_samples, y: max_ray_length, z: density, w: weight
    vec4 decay_and_exposure;    // x: decay, y: exposure, z: light_fade_start, w: light_fade_end
    vec4 ambient_color;         // rgb: ambient_col, w: camera_yaw
    vec4 near_fade_params;      // x: near_fade_start, y: near_fade_end, z: enable_near_fade, w: enable_near_gradient
    vec4 near_gradient_alpha;   // x: bottom_alpha, y: top_alpha, z: bottom_y, w: top_y
    vec4 near_gradient_curve;   // x: curve, y: enable_depth_blur, z: blur_near_dist, w: blur_far_dist
    vec4 depth_blur_and_anim;   // x: max_blur_radius, y: enable_animation, z: anim_scale, w: anim_intensity
    vec4 anim_blur_and_speed;   // x: anim_blur_radius, y: anim_speed, z: unused, w: unused
    vec4 screen_size;           // xy: screen_size, zw: 1.0 / screen_size
    vec4 inv_proj_zw;           // xy: inv_proj[2].zw, zw: inv_proj[3].zw
};

float bayer4x4(vec2 uv, vec2 viewport_size) {
    ivec2 p = ivec2(mod(uv * viewport_size, 4.0));
    int index = p.x + p.y * 4;
    float matrix[16] = float[](
        0.0/16.0,  8.0/16.0,  2.0/16.0, 10.0/16.0,
        12.0/16.0, 4.0/16.0, 14.0/16.0,  6.0/16.0,
        3.0/16.0, 11.0/16.0,  1.0/16.0,  9.0/16.0,
        15.0/16.0, 7.0/16.0, 13.0/16.0,  5.0/16.0
    );
    return matrix[index];
}

float sample_depth_value(vec2 uv, float default_val) {
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        return default_val;
    }
    return texture(depth_tex, uv).r;
}

float linearize_depth(float raw_depth) {
    if (raw_depth <= 1e-7) {
        return 10000.0; // Infinite sky
    }
    float view_z = inv_proj_zw.x * raw_depth + inv_proj_zw.y;
    float view_w = inv_proj_zw.z * raw_depth + inv_proj_zw.w;
    return -(view_z / max(abs(view_w), 1e-7));
}

float detect_godray_depth(vec2 uv, vec2 ray_dir) {
    float raw_depth = texture(depth_tex, uv).r;
    if (raw_depth > 1e-7) {
        return linearize_depth(raw_depth);
    }

    vec2 probe_dir = -ray_dir;
    float d1 = sample_depth_value(uv + probe_dir * 0.015, 0.0);
    if (d1 > 1e-7) return linearize_depth(d1);

    float d2 = sample_depth_value(uv + probe_dir * 0.040, 0.0);
    if (d2 > 1e-7) return linearize_depth(d2);

    float d3 = sample_depth_value(uv + probe_dir * 0.080, 0.0);
    if (d3 > 1e-7) return linearize_depth(d3);

    float horizon_dist = clamp(1.0 - abs(uv.y - 0.45) * 2.0, 0.0, 1.0);
    return mix(25.0, 100.0, horizon_dist);
}

float evaluate_anim_harmonic(float angle, float scale, float time_val) {
    float wave1 = sin(angle * scale + time_val);
    float wave2 = cos(angle * (scale * 1.618) - time_val * 0.618);
    return (wave1 + wave2 * 0.5) / 1.5;
}

void main() {
    ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = ivec2(screen_size.xy);

    if (pos.x >= size.x || pos.y >= size.y) {
        return;
    }

    // Early-out if facing away
    if (light_and_facing.z <= 0.001) {
        return;
    }

    vec2 uv = (vec2(pos) + vec2(0.5)) * screen_size.zw;

    float current_pixel_raw_depth = texture(depth_tex, uv).r;
    float current_pixel_dist = linearize_depth(current_pixel_raw_depth);

    // Near occlusion mask with down-to-up gradient
    float depth_mask = 1.0;
    if (near_fade_params.z > 0.5) { // enable_near_fade
        float dist_mask = smoothstep(near_fade_params.x, near_fade_params.y, current_pixel_dist);
        if (near_fade_params.w > 0.5) { // enable_near_gradient
            float vert_pos = 1.0 - uv.y;
            float vert_t = clamp((vert_pos - near_gradient_alpha.z) / max(near_gradient_alpha.w - near_gradient_alpha.z, 0.001), 0.0, 1.0);
            float vert_factor = pow(vert_t, near_gradient_curve.x);
            float gradient_alpha = mix(near_gradient_alpha.x, near_gradient_alpha.y, vert_factor);
            depth_mask = mix(gradient_alpha, 1.0, dist_mask);
        } else {
            depth_mask = dist_mask;
        }
    }

    // Direction and distance to sun
    vec2 to_sun = light_and_facing.xy - uv;
    float dist_to_sun = length(to_sun);
    vec2 ray_dir = to_sun / max(dist_to_sun, 0.0001);

    // World-anchored atmospheric animation modulation
    float anim_mod = 1.0;
    if (depth_blur_and_anim.y > 0.5) { // enable_animation
        float camera_yaw = ambient_color.w;
        float ray_angle = atan(to_sun.y, to_sun.x);
        float world_angle = ray_angle + camera_yaw;
        float time_val = light_and_facing.w * anim_blur_and_speed.y;

        float harmonic;
        if (anim_blur_and_speed.x > 0.001) {
            float h_center = evaluate_anim_harmonic(world_angle, depth_blur_and_anim.z, time_val);
            float h_pos = evaluate_anim_harmonic(world_angle + anim_blur_and_speed.x, depth_blur_and_anim.z, time_val);
            float h_neg = evaluate_anim_harmonic(world_angle - anim_blur_and_speed.x, depth_blur_and_anim.z, time_val);
            harmonic = h_center * 0.442 + (h_pos + h_neg) * 0.279;
        } else {
            harmonic = evaluate_anim_harmonic(world_angle, depth_blur_and_anim.z, time_val);
        }
        anim_mod = 1.0 + harmonic * depth_blur_and_anim.w;
    }

    // March distance clamping
    float march_dist = min(dist_to_sun * ray_params.z, ray_params.y);

    // Distance depth blur factor
    float detected_depth = detect_godray_depth(uv, ray_dir);
    float blur_factor = 0.0;
    if (near_gradient_curve.y > 0.5) { // enable_depth_blur
        blur_factor = smoothstep(near_gradient_curve.z, near_gradient_curve.w, detected_depth);
    }
    float current_blur_radius = blur_factor * depth_blur_and_anim.x;
    vec2 perp_dir = vec2(-ray_dir.y, ray_dir.x);

    // Dither noise
    float noise = bayer4x4(uv, screen_size.xy);

    // Raymarching
    int num_samples = int(ray_params.x);
    vec2 delta = (ray_dir * march_dist) / float(max(num_samples, 1));
    vec2 tex_coord = uv + delta * noise;

    vec3 color = vec3(0.0);
    float illumination_decay = 1.0;

    for (int i = 0; i < num_samples; i++) {
        tex_coord += delta;
        float t = float(i) / float(max(num_samples, 1));
        float occlusion;

        if (current_blur_radius > 0.0001) {
            vec2 blur_offset = perp_dir * (current_blur_radius * (0.6 + 0.4 * t));
            float scene_depth_center = sample_depth_value(tex_coord, 1.0);
            float scene_depth_pos = sample_depth_value(tex_coord + blur_offset, 1.0);
            float scene_depth_neg = sample_depth_value(tex_coord - blur_offset, 1.0);

            float occ_center = 1.0 - step(1e-10, scene_depth_center);
            float occ_pos = 1.0 - step(1e-10, scene_depth_pos);
            float occ_neg = 1.0 - step(1e-10, scene_depth_neg);
            occlusion = occ_center * 0.442 + (occ_pos + occ_neg) * 0.279;
        } else {
            float scene_depth = sample_depth_value(tex_coord, 1.0);
            occlusion = 1.0 - step(1e-10, scene_depth);
        }

        float sample_fade = 1.0 - smoothstep(decay_and_exposure.z, decay_and_exposure.w, t);
        color += ambient_color.rgb * occlusion * illumination_decay * ray_params.w * sample_fade;
        illumination_decay *= decay_and_exposure.x;
    }

    vec3 godray_rgb = color * decay_and_exposure.y * light_and_facing.z * depth_mask * anim_mod;

    // Additive blend with current frame color buffer
    if (dot(godray_rgb, vec3(1.0)) > 0.0001) {
        vec4 original_color = imageLoad(color_image, pos);
        vec3 blended_rgb = original_color.rgb + godray_rgb;
        imageStore(color_image, pos, vec4(blended_rgb, original_color.a));
    }
}
