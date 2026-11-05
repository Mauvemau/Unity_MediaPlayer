Shader "Effects/CRT"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}
        
        [Header(Rectangular Vignette)]
        _VignetteLength("Vignette Length", Range(0.1, 0.5)) = 0.45
        _VignetteHeight("Vignette Height", Range(0.1, 0.5)) = 0.45
        _VignetteRoundness("Vignette Roundness", Range(0.0, 0.2)) = 0.05
        _VignetteIntensity("Vignette Intensity", Range(0.0, 10.0)) = 2.0

        [Header(CRT Effects)]
        _ScanlineIntensity("Scanline Intensity", Range(0.0, 1.0)) = 0.4
        _ScanlineCount("Scanline Count", Float) = 240.0
        _MaskStrength("Mask Strength", Range(0.0, 1.0)) = 0.3
        _MaskSize("Mask Size", Range(1.0, 4.0)) = 1.0

        [Header(Bloom and Bleed)]
        _AberrationStrength("Chromatic Aberration", Range(0.0, 0.01)) = 0.002
        _BloomIntensity("Phosphor Bloom Intensity", Range(0.0, 1.0)) = 0.3

        [Header(CRT Flicker)]
        _FlickerIntensity("Flicker Intensity", Range(0.0, 0.1)) = 0.015
        _FlickerSpeed("Flicker Speed", Float) = 40.0

        [Header(Glass Specular)]
        _GlossIntensity("Gloss Intensity", Range(0.0, 2.0)) = 0.6
        _GlossPower("Shininess (Exponent)", Range(32.0, 512.0)) = 256.0
        _FresnelStrength("Fresnel Strength", Range(0.0, 1.0)) = 0.4

        [Header(Signal Loss Static)]
        _StaticIntensity("Noise Intensity", Range(0.0, 10.0)) = 0.0
        _StaticSpeed("Static Speed", Float) = 1.0
        _StaticResolution("Static Grain Blockiness", Range(64.0, 512.0)) = 200.0

        [Header(Horizontal Tear)]
        _JitterIntensity("Jitter Intensity", Range(0.0, 1.0)) = 0.0
        _JitterSpeed("Jitter Speed", Float) = 15.0
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 positionWS  : TEXCOORD1;
                float3 normalWS    : TEXCOORD2;
                float2 uv          : TEXCOORD0;
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);
            
            float4 _BaseMap_TexelSize;

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                float4 _BaseMap_ST;
                float _VignetteLength;
                float _VignetteHeight;
                float _VignetteRoundness;
                float _VignetteIntensity;
                float _ScanlineIntensity;
                float _ScanlineCount;
                float _MaskStrength;
                float _MaskSize;
                float _AberrationStrength;
                float _BloomIntensity;
                float _FlickerIntensity;
                float _FlickerSpeed;
                float _GlossIntensity;
                float _GlossPower;
                float _FresnelStrength;
                float _StaticIntensity;
                float _StaticSpeed;
                float _StaticResolution;
                float _JitterIntensity;
                float _JitterSpeed;
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.positionWS  = TransformObjectToWorld(IN.positionOS.xyz);
                OUT.normalWS    = TransformObjectToWorldNormal(IN.normalOS);
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                return OUT;
            }

            // Stable UV-space Phosphor Triad Mask
            float3 GetPhosphorMask(float2 uv)
            {
                float xCoord = uv.x * 640.0 / _MaskSize;
                int columnIndex = (int)fmod(floor(xCoord), 3.0);

                float3 mask;
                if (columnIndex == 0)
                    mask = float3(1.0, 0.2, 0.2); 
                else if (columnIndex == 1)
                    mask = float3(0.2, 1.0, 0.2); 
                else
                    mask = float3(0.2, 0.2, 1.0); 

                return mask;
            }

            #define GLOW_FALLOFF 0.35
            float GetKernelWeight(float x)
            {
                return exp(-GLOW_FALLOFF * x * x);
            }

            // Simplex Noise Functions
            float3 mod289(float3 x) {
                return x - floor(x * (1.0 / 289.0)) * 289.0;
            }

            float2 mod289(float2 x) {
                return x - floor(x * (1.0 / 289.0)) * 289.0;
            }

            float3 permute(float3 x) {
                return mod289(((x * 34.0) + 1.0) * x);
            }

            float snoise(float2 v) {
                const float4 C = float4(0.211324865405187, 0.366025403784439, -0.577350269189626, 0.024390243902439);
                float2 i  = floor(v + dot(v, C.yy));
                float2 x0 = v - i + dot(i, C.xx);
                float2 i1 = (x0.x > x0.y) ? float2(1.0, 0.0) : float2(0.0, 1.0);
                float4 x12 = x0.xyxy + C.xxzz;
                x12.xy -= i1;
                i = mod289(i);
                float3 p = permute(permute(i.y + float3(0.0, i1.y, 1.0)) + i.x + float3(0.0, i1.x, 1.0));
                float3 m = max(0.5 - float3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.0);
                m = m * m;
                m = m * m;
                float3 x = 2.0 * frac(p * C.www) - 1.0;
                float3 h = abs(x) - 0.5;
                float3 ox = floor(x + 0.5);
                float3 a0 = x - ox;
                m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
                float3 g;
                g.x  = a0.x  * x0.x  + h.x  * x0.y;
                g.yz = a0.yz * x12.xz + h.yz * x12.yw;
                return 130.0 * dot(m, g);
            }

            // Non-banding hash with coordinate wrapping to prevent floating-point drift
            float hashNoise(float2 p)
            {
                p = fmod(p, 500.0); // Prevents precision loss over time
                float2 q = frac(p * float2(443.897, 441.423));
                q += dot(q, q.yx + 19.19);
                return frac(q.x * q.y);
            }

            half4 frag(Varyings IN) : SV_Target
            {
                // 0. Horizontal Jitter / Tear (Loss of Sync)
                float2 glitchUV = IN.uv;
                if (_JitterIntensity > 0.001)
                {
                    float jitterTime = _Time.y * _JitterSpeed;
                    float fuzzOffset = snoise(float2(jitterTime, IN.uv.y * 80.0));
                    float largeJitter = step(0.90, snoise(float2(_Time.y * 2.5, IN.uv.y * 6.0))) * snoise(float2(_Time.y * 20.0, 1.0));
                    
                    float xJitterOffset = (fuzzOffset * 0.003 + largeJitter * 0.07) * _JitterIntensity;
                    glitchUV.x += xJitterOffset;
                }

                // 1. Chromatic Aberration (Using glitched UVs)
                float2 uvCenter = glitchUV - 0.5;
                float2 uvR = glitchUV + uvCenter * _AberrationStrength;
                float2 uvB = glitchUV - uvCenter * _AberrationStrength;

                half r = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uvR).r;
                half g = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, glitchUV).g;
                half4 texColor = half4(r, g, SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uvB).b, 1.0) * _BaseColor;

                // 1.5. True Organic Analog Static (Continuous flow, zero pattern repetition)
                if (_StaticIntensity > 0.001)
                {
                    // Wrapped continuous time loop
                    float t = fmod(_Time.y * _StaticSpeed * 15.0, 100.0);

                    // Proportional grid block scaling matching 4:3
                    float2 gridRes = float2(_StaticResolution * 1.3333, _StaticResolution);
                    float2 blockUV = floor(glitchUV * gridRes);

                    // Multi-layer chaotic scrambling offset by independent prime multipliers
                    float noise1 = hashNoise(blockUV + float2(t * 19.13, t * 47.89));
                    float noise2 = hashNoise(floor(glitchUV * gridRes * 0.7) - float2(t * 31.23, t * 13.71));

                    // Combine layers into genuine, chaotic television snow
                    float combinedStatic = saturate(noise1 * 0.6 + noise2 * 0.4);

                    texColor.rgb += combinedStatic * _StaticIntensity * 0.6;
                }

                // 2. Phosphor Bloom / Halation
                half3 bloomSum = 0.0;
                float weightSum = 0.0;
                float2 texelSize = _BaseMap_TexelSize.xy * 1.5; 

                for (float x = -2.0; x <= 2.0; x++)
                {
                    for (float y = -2.0; y <= 2.0; y++)
                    {
                        float2 offset = float2(x, y) * texelSize;
                        float weight = GetKernelWeight(x) * GetKernelWeight(y);
                        
                        half3 sampleCol = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, glitchUV + offset).rgb;
                        float luma = dot(sampleCol, float3(0.299, 0.587, 0.114));
                        float threshold = saturate((luma - 0.3) * 3.0);
                        
                        bloomSum += sampleCol * threshold * weight;
                        weightSum += weight;
                    }
                }
                half3 phosphorBloom = bloomSum / max(weightSum, 0.0001);
                texColor.rgb += phosphorBloom * _BloomIntensity;

                // 3. Scanlines Effect
                float scanline = sin(IN.uv.y * _ScanlineCount * 3.14159265 * 2.0);
                scanline = scanline * 0.5 + 0.5;
                float3 scanlineColor = texColor.rgb * lerp(1.0, scanline, _ScanlineIntensity);

                // 4. Phosphor Triads (Shadow Mask)
                float3 mask = GetPhosphorMask(IN.uv);
                float3 maskedColor = lerp(scanlineColor, scanlineColor * mask, _MaskStrength);

                // 5. Rounded Rectangle Vignette
                float2 d = abs(uvCenter) - (float2(_VignetteLength, _VignetteHeight) - _VignetteRoundness);
                float dist = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - _VignetteRoundness;
                float vignetteFactor = saturate(dist * _VignetteIntensity * 10.0);
                
                half3 finalRgb = lerp(maskedColor, 0.0, vignetteFactor);

                // 6. Analog Refresh Flicker
                float flicker = 1.0 + sin(_Time.y * _FlickerSpeed + IN.uv.y * 20.0) * _FlickerIntensity;
                finalRgb *= flicker;

                // 7. Polished Glass Specular & Fresnel Rim Reflection
                float3 virtualLightDir = normalize(float3(0.0, 1.0, -1.0));
                float3 normalWS = normalize(IN.normalWS);
                float3 viewDirWS = normalize(_WorldSpaceCameraPos - IN.positionWS);
                
                float3 halfDir = normalize(virtualLightDir + viewDirWS);
                float NdotH = saturate(dot(normalWS, halfDir));
                float specular = pow(NdotH, _GlossPower) * _GlossIntensity;

                float NdotV = saturate(dot(normalWS, viewDirWS));
                float fresnel = pow(1.0 - NdotV, 4.0) * _FresnelStrength;

                finalRgb += float3(1.0, 1.0, 1.0) * (specular + fresnel);

                return half4(finalRgb, texColor.a);
            }
            ENDHLSL
        }
    }
}