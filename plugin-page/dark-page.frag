#version 440
// A PDF's page in the theme's colours (plan.md item 15, step 4): white paper
// becomes the theme's ground, black ink its text, by the lightness alone;
// what colour a figure has is kept, so a chart's red is still red and a
// photo is not a negative. Compiled with qsb into dark-page.frag.qsb (the
// Air has no qsb: `qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o
// dark-page.frag.qsb dark-page.frag` on a machine that has).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 ground;
    vec4 ink;
};
layout(binding = 1) uniform sampler2D source;

void main() {
    vec4 c = texture(source, qt_TexCoord0);
    vec3 rgb = c.a > 0.0 ? c.rgb / c.a : c.rgb;
    float y = dot(rgb, vec3(0.299, 0.587, 0.114));
    vec3 chroma = rgb - vec3(y);
    vec3 base = mix(ground.rgb, ink.rgb, 1.0 - y);
    vec3 out_rgb = clamp(base + chroma * 0.85, 0.0, 1.0);
    fragColor = vec4(out_rgb * c.a, c.a) * qt_Opacity;
}
