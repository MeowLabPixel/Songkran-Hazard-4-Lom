#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Binding 0: Destination color image (read & write)
layout(rgba16f, set = 0, binding = 0) uniform image2D color_image;

// Binding 1: Depth texture
layout(set = 0, binding = 1) uniform sampler2D depth_tex;

// Binding 2: Normal & Roughness texture
layout(set = 0, binding = 2) uniform sampler2D normal_roughness_tex;

// Push Constants (112 bytes, safely under the 128-byte Vulkan guarantee)
layout(push_constant, std430) uniform Params {
    vec4 outline_color;      // r, g, b, a
    vec4 edge_thresholds;    // x: depth_threshold, y: normal_threshold, z: normal_smoothing, w: has_normals (1.0 or 0.0)
    vec4 dist_params;        // x: min_distance, y: max_distance, z: min_thickness, w: max_thickness
    vec4 screen_size;        // x: width, y: height, z: 1.0/width, w: 1.0/height
    vec4 inv_proj_zw;        // x: inv_proj[2].z, y: inv_proj[3].z, z: inv_proj[2].w, w: inv_proj[3].w
    vec4 inv_proj_xy;        // x: inv_proj[0].x, y: inv_proj[1].y, z: unused, w: unused
    vec4 grazing_params;     // x: fresnel_power, y: angle_mask_power, z: modulation_factor, w: unused
} params;

// Godot normal-roughness buffer unpacking
vec3 unpack_normal(vec4 raw_nr) {
    return normalize(raw_nr.xyz * 2.0 - 1.0);
}

float get_linear_depth(float depth) {
    if (depth <= 1e-7) {
        return 10000.0; // Infinite background / sky
    }
    float view_z = params.inv_proj_zw.x * depth + params.inv_proj_zw.y;
    float view_w = params.inv_proj_zw.z * depth + params.inv_proj_zw.w;
    return -(view_z / max(abs(view_w), 1e-7));
}

float remap(float v, float from1, float to1, float from2, float to2) {
    return (v - from1) / max(to1 - from1, 1e-5) * (to2 - from2) + from2;
}

float fresnel(float amount, vec3 normal, vec3 view) {
    return pow(1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0), amount);
}

float get_grazing_modulation(vec3 pixel_normal, vec3 view_dir) {
    if (params.edge_thresholds.w < 0.5) {
        return 1.0;
    }
    float f = fresnel(params.grazing_params.x, pixel_normal, view_dir);
    float x = clamp(((f - 1.0) / max(params.grazing_params.y, 1e-4)) + 1.0, 0.0, 1.0);
    return (x + params.grazing_params.z) + 1.0;
}

void main() {
    ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = ivec2(params.screen_size.xy);

    if (pos.x >= size.x || pos.y >= size.y) {
        return;
    }

    vec2 uv = (vec2(pos) + vec2(0.5)) * params.screen_size.zw;
    float aspect = params.screen_size.y * params.screen_size.z;

    // 1. Center depth sample to determine adaptive thickness & distance fade
    float c_raw_depth = texture(depth_tex, uv).r;
    float c_depth = get_linear_depth(c_raw_depth);

    // Skip infinite sky
    if (c_depth >= 9999.0) {
        return;
    }

    float thickness = clamp(
        remap(c_depth, params.dist_params.x, params.dist_params.y, params.dist_params.w, params.dist_params.z),
        params.dist_params.z,
        params.dist_params.w
    );

    float fade_a = clamp(
        remap(c_depth, params.dist_params.x, params.dist_params.y, 1.0, 0.0),
        0.0,
        1.0
    );

    if (fade_a <= 0.001) {
        return;
    }

    vec2 h_offset = vec2(thickness * aspect * 0.001, 0.0);
    vec2 v_offset = vec2(0.0, thickness * 0.001);

    // 2. Sample 8 neighboring depth values
    float d_l  = get_linear_depth(texture(depth_tex, uv - h_offset).r);
    float d_r  = get_linear_depth(texture(depth_tex, uv + h_offset).r);
    float d_u  = get_linear_depth(texture(depth_tex, uv - v_offset).r);
    float d_d  = get_linear_depth(texture(depth_tex, uv + v_offset).r);
    float d_tl = get_linear_depth(texture(depth_tex, uv - h_offset + v_offset).r);
    float d_tr = get_linear_depth(texture(depth_tex, uv + h_offset + v_offset).r);
    float d_bl = get_linear_depth(texture(depth_tex, uv - h_offset - v_offset).r);
    float d_br = get_linear_depth(texture(depth_tex, uv + h_offset - v_offset).r);

    float n_total = d_l + d_r + d_u + d_d + d_tl + d_tr + d_bl + d_br;
    float depth_diff = n_total - (c_depth * 8.0);

    // 3. Reconstruct view ray and calculate grazing angle modulation
    vec3 pixel_normal = vec3(0.0, 0.0, 1.0);
    if (params.edge_thresholds.w > 0.5) {
        pixel_normal = unpack_normal(texture(normal_roughness_tex, uv));
    }

    vec2 ndc_xy = uv * 2.0 - 1.0;
    vec3 ray_dir = normalize(vec3(ndc_xy.x * params.inv_proj_xy.x, ndc_xy.y * params.inv_proj_xy.y, -1.0));
    vec3 view_dir = -ray_dir;

    float grazing_mod = get_grazing_modulation(pixel_normal, view_dir);
    float depth_threshold = params.edge_thresholds.x * grazing_mod;
    float depth_edge = step(depth_threshold, depth_diff);

    // 4. Normal edge detection (if normal buffer available)
    float norm_edge = 0.0;
    if (params.edge_thresholds.w > 0.5) {
        vec3 n_l  = unpack_normal(texture(normal_roughness_tex, uv - h_offset));
        vec3 n_r  = unpack_normal(texture(normal_roughness_tex, uv + h_offset));
        vec3 n_u  = unpack_normal(texture(normal_roughness_tex, uv - v_offset));
        vec3 n_d  = unpack_normal(texture(normal_roughness_tex, uv + v_offset));
        vec3 n_tl = unpack_normal(texture(normal_roughness_tex, uv - h_offset + v_offset));
        vec3 n_tr = unpack_normal(texture(normal_roughness_tex, uv + h_offset + v_offset));
        vec3 n_bl = unpack_normal(texture(normal_roughness_tex, uv - h_offset - v_offset));
        vec3 n_br = unpack_normal(texture(normal_roughness_tex, uv + h_offset - v_offset));

        vec3 diff0 = n_tr - n_bl;
        vec3 diff1 = n_tl - n_br;
        vec3 diff2 = n_l  - n_r;
        vec3 diff3 = n_u  - n_d;

        float edge_normal = sqrt(dot(diff0, diff0) + dot(diff1, diff1) + dot(diff2, diff2) + dot(diff3, diff3));
        float n_thresh = params.edge_thresholds.y;
        float n_smooth = params.edge_thresholds.z;
        norm_edge = smoothstep(n_thresh - n_smooth, n_thresh + n_smooth, edge_normal);
    }

    float edge_alpha = max(depth_edge, norm_edge) * params.outline_color.a * fade_a;

    if (edge_alpha > 0.001) {
        vec4 original_color = imageLoad(color_image, pos);
        vec3 blended_rgb = mix(original_color.rgb, params.outline_color.rgb, edge_alpha);
        imageStore(color_image, pos, vec4(blended_rgb, original_color.a));
    }
}
