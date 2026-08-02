//
//  ShaderTypes.h
//  LunarLander
//
//  Shared types between Metal shaders and Swift code
//

#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
typedef metal::int32_t EnumBackingType;
#else
#import <Foundation/Foundation.h>
typedef NSInteger EnumBackingType;
#endif

#include <simd/simd.h>

// Vertex with position and color
typedef struct {
    vector_float2 position;
    vector_float4 color;
} Vertex2D;

// Vertex with position and texture coordinates
typedef struct {
    vector_float2 position;
    vector_float2 texCoord;
} VertexUV;

// Uniforms for 2D rendering
typedef struct {
    vector_float2 viewportSize;
} Uniforms2D;

#endif /* ShaderTypes_h */
