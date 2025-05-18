#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict buffer Canvas {
	float value[];
} canvas;

layout(binding = 1, std140) uniform StructuralInfo {
	int width;
	int height;
};

layout(binding = 2, std140) uniform DynamicInfo {
	float l_position_x, l_position_y, l_velocity_x, l_velocity_y, l_tilt_x, l_tilt_y, l_pressure, l_time;
	float position_x, position_y, velocity_x, velocity_y, tilt_x, tilt_y, pressure, time;
};

void main() {
	if (gl_GlobalInvocationID.x >= width || gl_GlobalInvocationID.y >= height) {
		return;
	}
	float max_dist = height * height + width * width;
	int idx = int(gl_GlobalInvocationID.y) * width + int(gl_GlobalInvocationID.x);
	vec2 p = gl_GlobalInvocationID.xy;
	vec2 a = vec2(position_x, position_y);
	vec2 b = vec2(l_position_x, l_position_y);
	vec2 pa = p - a, ba = b - a;
	float h = clamp( dot(pa, ba) / dot(ba, ba), 0.0, 1.0 );
	float l = length( pa - ba * h );
	float c = canvas.value[idx];
	canvas.value[idx] = isnan(c) ? l : min(c, l);
}
