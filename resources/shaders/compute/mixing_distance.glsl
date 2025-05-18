#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict buffer Rollback {
	vec4 value[];
} rollback;

layout(set = 0, binding = 1, std430) restrict buffer Commit {
	vec4 value[];
} commit;

layout(set = 0, binding = 2, std430) restrict buffer Canvas {
	float value[];
} canvas;

layout(set = 0, binding = 3, std140) uniform StructuralInfo {
	int width;
	int height;
};

layout(set = 0, binding = 4, std140) uniform Parameters {
	vec4 color;
	float radius;
	float sharpness;
};

const mat3 kCONEtoLMS = mat3(
	vec3(0.4121656120,  0.2118591070,  0.0883097947),
	vec3(0.5362752080,  0.6807189584,  0.2818474174),
	vec3(0.0514575653,  0.1074065790,  0.6302613616));
const mat3 kLMStoCONE = mat3(
	vec3(4.0767245293, -1.2681437731, -0.0041119885),
	vec3(-3.3072168827,  2.6093323231, -0.7034763098),
	vec3(0.2307590544, -0.3411344290,  1.7068625689));

const vec3 ONE_THIRD = vec3(1./3.);

vec3 oklab_mix(vec3 colA, vec3 colB, float h)
{
    vec3 lmsA = pow( kCONEtoLMS*colA, ONE_THIRD );
    vec3 lmsB = pow( kCONEtoLMS*colB, ONE_THIRD );
    // lerp
    vec3 lms = mix( lmsA, lmsB, h );
    // gain in the middle (no oaklab anymore, but looks better?)
 // lms *= 1.0+0.2*h*(1.0-h);
    // cone to rgb
    return kLMStoCONE*(lms*lms*lms);
}

void main() {
	if (gl_GlobalInvocationID.x >= width || gl_GlobalInvocationID.y >= height) {
		return;
	}
	float max_dist = height*height + width*width;
	int idx = int(gl_GlobalInvocationID.y) * width + int(gl_GlobalInvocationID.x);
	float ratio = 1. - (canvas.value[idx] / radius);
	if (ratio < 0.) return;
	ratio = 1. - pow(1. - ratio, sharpness);
	ratio *= color.a;
	float total_alpha = min(1., ratio + rollback.value[idx].a);
	if (total_alpha < 0.003) return;
	vec3 new_color = oklab_mix(rollback.value[idx].rgb, color.rgb, ratio / total_alpha);
	commit.value[idx] = vec4(new_color, max(rollback.value[idx].a, total_alpha));
}
