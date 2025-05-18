#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 0, std140) uniform StructuralInfo {
	int width;
	int height;
};

layout(set = 0, binding = 1, std140) uniform BrushInfo {
	vec4 color;
	float size_min;
	float size_max;
	float opacity;
};

layout(set = 0, binding = 2, std140) uniform CursorInfo {
	float l_position_x, l_position_y, l_velocity_x, l_velocity_y, l_tilt_x, l_tilt_y, l_pressure, l_time;
	float position_x, position_y, velocity_x, velocity_y, tilt_x, tilt_y, pressure, time;
};

layout(set = 0, binding = 3, std430) restrict buffer Commit {
		vec4 value[];
} commit;

const float time_resolution = 1. / 3600.;

void main() {
	if (gl_GlobalInvocationID.x >= width || gl_GlobalInvocationID.y >= height) {
		return;
	}
	int idx = int(gl_GlobalInvocationID.y) * width + int(gl_GlobalInvocationID.x);
	vec2 p = gl_GlobalInvocationID.xy;

	vec2 lpos = vec2(l_position_x, l_position_y);
	vec2 npos = vec2(position_x, position_y);

	float time_diff = time - l_time;
	float iterations = max(time_diff / time_resolution, 1.);
	float step = 1. / iterations;

	vec2 lvel = vec2(l_velocity_x, l_velocity_y) * time_diff;
	vec2 nvel = vec2(velocity_x, velocity_y) * time_diff;

	for (float t = step; t < 1.; t += step) {
		vec2 center = mix(lpos, npos, t);
		float dist = length(center - p);

		float current_pressure = mix(pressure, l_pressure, t);
		float sz = mix(size_min, size_max, current_pressure);
		if(dist < sz) {
			commit.value[idx].a *= 1. - (opacity * step);
		}
	}
}
