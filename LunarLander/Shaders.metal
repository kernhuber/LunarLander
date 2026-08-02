//
//  Shaders.metal
//  LunarLander
//
//  2D vertex and fragment shaders for the Lunar Lander game
//

#include <metal_stdlib>
#include <simd/simd.h>
#import "ShaderTypes.h"

using namespace metal;

typedef struct {
    float4 position [[position]];
    float4 color;
    float pointSize [[point_size]];
} RasterizerData;

// 2D vertex shader - transforms pixel coordinates to clip space
vertex RasterizerData vertexShader2D(uint vertexID [[vertex_id]],
                                     constant Vertex2D *vertices [[buffer(0)]],
                                     constant Uniforms2D &uniforms [[buffer(1)]]) {
    RasterizerData out;

    float2 pixelPos = vertices[vertexID].position;
    // Convert pixel coordinates to clip space (-1 to 1)
    float2 clipPos = (pixelPos / (uniforms.viewportSize / 2.0)) - 1.0;
    out.position = float4(clipPos.x, clipPos.y, 0.0, 1.0);
    out.color = vertices[vertexID].color;
    out.pointSize = 3.0;

    return out;
}

// Simple fragment shader - outputs vertex color
fragment float4 fragmentShader2D(RasterizerData in [[stage_in]]) {
    return in.color;
}

// Star fragment shader - circular point with glow
fragment float4 starFragmentShader(RasterizerData in [[stage_in]],
                                    float2 pointCoord [[point_coord]]) {
    float2 center = pointCoord - float2(0.5);
    float dist = length(center);
    if (dist > 0.5) discard_fragment();
    float alpha = 1.0 - smoothstep(0.0, 0.5, dist);
    return float4(in.color.rgb, in.color.a * alpha);
}

// Texture vertex shader - for logo display
typedef struct {
    float4 position [[position]];
    float2 texCoord;
} TextureRasterizerData;

vertex TextureRasterizerData textureVertexShader(uint vertexID [[vertex_id]],
                                                  constant VertexUV *vertices [[buffer(0)]],
                                                  constant Uniforms2D &uniforms [[buffer(1)]]) {
    TextureRasterizerData out;
    float2 pixelPos = vertices[vertexID].position;
    float2 clipPos = (pixelPos / (uniforms.viewportSize / 2.0)) - 1.0;
    out.position = float4(clipPos.x, clipPos.y, 0.0, 1.0);
    out.texCoord = vertices[vertexID].texCoord;
    return out;
}

// Texture fragment shader - samples texture
fragment float4 textureFragmentShader(TextureRasterizerData in [[stage_in]],
                                       texture2d<float> tex [[texture(0)]]) {
    constexpr sampler s(mag_filter::linear, min_filter::linear);
    return tex.sample(s, in.texCoord);
}
