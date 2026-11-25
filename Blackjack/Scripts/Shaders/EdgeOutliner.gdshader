
shader_type spatial;
render_mode unshaded, fog_disabled, depth_draw_never, depth_test_disabled;
stencil_mode read, compare_not_equal, 1;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

uniform vec3 line_color : source_color = vec3(0.4);
uniform vec3 background_color : source_color = vec3(0.9);

// Overall thickness
uniform float line_thickness : hint_range(1.0, 12.0, 0.5) = 2.0;

// Major depth edges
uniform float depth_threshold : hint_range(0.001, 0.25, 0.001) = 0.05;

// Higher = reject more ordinary surface slopes
uniform float occlusion_ratio : hint_range(1.0, 10.0, 0.5) = 3.0;

// Optional interior geometry lines
uniform bool draw_crease_lines = false;
uniform float normal_threshold : hint_range(0.01, 1.0, 0.01) = 0.30;

// Optional texture detail lines
uniform bool detect_color_edges = false;
uniform float color_threshold : hint_range(0.01, 1.0, 0.01) = 0.18;

const vec2 AXES[4] = {
    vec2(1.0, 0.0),
    vec2(0.0, 1.0),
    vec2(0.707107, 0.707107),
    vec2(0.707107, -0.707107)
};

vec2 safe_uv(vec2 uv, vec2 pixel_size) {
    vec2 half_pixel = pixel_size * 0.5;
    return clamp(uv, half_pixel, vec2(1.0) - half_pixel);
}

// Compatibility renderer: OpenGL NDC coordinates.
vec3 get_view_position(vec2 uv, mat4 inv_projection) {
    float raw_depth = textureLod(depth_texture, uv, 0.0).r;

    vec3 ndc = vec3(uv, raw_depth) * 2.0 - 1.0;
    vec4 view = inv_projection * vec4(ndc, 1.0);

    return view.xyz / view.w;
}

// Negative value means empty background.
float get_linear_depth(vec2 uv, mat4 inv_projection) {
    float raw_depth = textureLod(depth_texture, uv, 0.0).r;

    if (raw_depth <= 0.000001) {
        return -1.0;
    }

    vec3 ndc = vec3(uv, raw_depth) * 2.0 - 1.0;
    vec4 view = inv_projection * vec4(ndc, 1.0);

    return -view.z / view.w;
}

void vertex() {
    POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
    vec2 uv = SCREEN_UV;
    vec2 pixel_size = 1.0 / VIEWPORT_SIZE;
    float radius = max(1.0, line_thickness * 0.5);

    float center_depth = get_linear_depth(
        uv, INV_PROJECTION_MATRIX
    );

    float edge = 0.0;

    vec3 center_color = vec3(0.0);

    if (detect_color_edges) {
        center_color = textureLod(screen_texture, uv, 0.0).rgb;
    }

    // PASS 1: Silhouette and major occlusion lines.
    for (int i = 0; i < 4; i++) {
        vec2 offset = AXES[i] * pixel_size * radius;

        vec2 uv_a = safe_uv(uv - offset, pixel_size);
		vec2 uv_b = safe_uv(uv + offset, pixel_size);

        float depth_a = get_linear_depth(
            uv_a, INV_PROJECTION_MATRIX
        );

        float depth_b = get_linear_depth(
            uv_b, INV_PROJECTION_MATRIX
        );

        // Object-to-background boundaries.
        if (center_depth < 0.0) {
            if (depth_a > 0.0 || depth_b > 0.0) {
                edge = 1.0;
            }
        } else if (depth_a < 0.0 || depth_b < 0.0) {
            edge = 1.0;
        } else {
            // Compare opposite depth changes.
            // A smooth slope tends to change equally
            // in both directions.
            float diff_a = abs(center_depth - depth_a);
            float diff_b = abs(center_depth - depth_b);

            float scale = max(
                min(center_depth, min(depth_a, depth_b)),
                0.01
            );

            diff_a /= scale;
            diff_b /= scale;

            float largest = max(diff_a, diff_b);
            float smallest = min(diff_a, diff_b);

            // Strong, asymmetric depth changes are
            // more likely to be occlusion boundaries.
            if (
                largest > depth_threshold &&
                largest > smallest * occlusion_ratio + 0.00001
            ) {
                edge = 1.0;
            }
        }

        // Optional edges from rendered colors.
        if (detect_color_edges && edge < 0.5) {
            vec3 color_a = textureLod(
                screen_texture, uv_a, 0.0
            ).rgb;

            vec3 color_b = textureLod(
                screen_texture, uv_b, 0.0
            ).rgb;

            float difference = max(
                length(center_color - color_a),
                length(center_color - color_b)
            );

            if (difference > color_threshold) {
                edge = 1.0;
            }
        }

        if (edge > 0.5) {
            break;
        }
    }

    // PASS 2: Optional sharp geometric creases.
    // Disabled by default to avoid outlining every edge.
    if (draw_crease_lines && edge < 0.5 && center_depth > 0.0) {
        vec2 ox = vec2(pixel_size.x * radius, 0.0);
        vec2 oy = vec2(0.0, pixel_size.y * radius);

        vec2 uv_l = safe_uv(uv - ox, pixel_size);
		vec2 uv_r = safe_uv(uv + ox, pixel_size);
		vec2 uv_u = safe_uv(uv - oy, pixel_size);
		vec2 uv_d = safe_uv(uv + oy, pixel_size);

        float dl = get_linear_depth(uv_l, INV_PROJECTION_MATRIX);
        float dr = get_linear_depth(uv_r, INV_PROJECTION_MATRIX);
        float du = get_linear_depth(uv_u, INV_PROJECTION_MATRIX);
        float dd = get_linear_depth(uv_d, INV_PROJECTION_MATRIX);

        if (min(min(dl, dr), min(du, dd)) > 0.0) {
            vec3 c = get_view_position(uv, INV_PROJECTION_MATRIX);
            vec3 l = get_view_position(uv_l, INV_PROJECTION_MATRIX);
            vec3 r = get_view_position(uv_r, INV_PROJECTION_MATRIX);
            vec3 u = get_view_position(uv_u, INV_PROJECTION_MATRIX);
            vec3 d = get_view_position(uv_d, INV_PROJECTION_MATRIX);

            vec3 cross_a = cross(c - l, u - c);
            vec3 cross_b = cross(r - c, c - d);

            if (length(cross_a) > 0.00000001 &&
                length(cross_b) > 0.00000001) {

                vec3 n1 = normalize(cross_a);
                vec3 n2 = normalize(cross_b);

                float crease = 1.0 - clamp(
                    dot(n1, n2), -1.0, 1.0
                );

                if (crease > normal_threshold) {
                    edge = 1.0;
                }
            }
        }
    }

    ALBEDO = mix(background_color, line_color, edge);
    ALPHA = 1.0;
}
