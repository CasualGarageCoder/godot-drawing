#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba32f) uniform restrict writeonly image2D output_tex;

layout(set = 0, binding = 1, std430) restrict buffer Canvas {
	vec4 value[];
} canvas;

layout(set = 0, binding = 2, std140) uniform StructuralInfo {
	int width;
	int height;
};

void main() {
	if (gl_GlobalInvocationID.x >= width || gl_GlobalInvocationID.y >= height) {
		return;
	}
	int idx = int(gl_GlobalInvocationID.y) * width + int(gl_GlobalInvocationID.x);

	// Simpliest case.
	// Could be a [0..1[ to [0..255] convertion in case of RGBA8 texture.
	// Could have been a CYMK -> RBG convertion.
	imageStore(output_tex, ivec2(gl_GlobalInvocationID.xy), canvas.value[idx]);
}
