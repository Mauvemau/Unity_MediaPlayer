Shader "Effects/CRT"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}
        
        [Header(Rounded Rectangular Vignette)]
        _VignetteLength("Vignette Length", Range(0.1, 0.5)) = 0.45
        _VignetteHeight("Vignette Height", Range(0.1, 0.5)) = 0.45
        _VignetteRoundness("Vignette Roundness", Range(0.0, 0.2)) = 0.05
        _VignetteIntensity("Vignette Intensity", Range(0.0, 10.0)) = 2.0

        [Header(CRT Retro Effects)]
        _ScanlineIntensity("Scanline Intensity", Range(0.0, 1.0)) = 0.4
        _ScanlineCount("Scanline Count", Float) = 240.0
        _MaskStrength("Mask Strength (Triads)", Range(0.0, 1.0)) = 0.3
        _MaskSize("Mask Size", Range(1.0, 4.0)) = 1.0

        [Header(Color and Light Bleed)]
        _AberrationStrength("Chromatic Aberration (RGB Shift)", Range(0.0, 0.01)) = 0.002
        _BloomIntensity("Phosphor Bloom Intensity", Range(0.0, 1.0)) = 0.3

        [Header(CRT Flicker)]
        _FlickerIntensity("Flicker Intensity", Range(0.0, 0.1)) = 0.015
        _FlickerSpeed("Flicker Speed", Float) = 40.0

        [Header(Glass Specular and Fresnel)]
        _GlossIntensity("Glass Gloss Intensity", Range(0.0, 2.0)) = 0.6
        _GlossPower("Glass Shininess (Exponent)", Range(32.0, 512.0)) = 256.0
        _FresnelStrength("Glass Fresnel Strength", Range(0.0, 1.0)) = 0.4
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

            half4 frag(Varyings IN) : SV_Target
            {
                // 1. Chromatic Aberration
                float2 uvCenter = IN.uv - 0.5;
                float2 uvR = IN.uv + uvCenter * _AberrationStrength;
                float2 uvB = IN.uv - uvCenter * _AberrationStrength;

                half r = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uvR).r;
                half g = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv).g;
                half b = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uvB).b;
                half4 texColor = half4(r, g, b, 1.0) * _BaseColor;

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
                        
                        half3 sampleCol = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv + offset).rgb;
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
                
                // Sharp Specular Glint
                float3 halfDir = normalize(virtualLightDir + viewDirWS);
                float NdotH = saturate(dot(normalWS, halfDir));
                float specular = pow(NdotH, _GlossPower) * _GlossIntensity;

                // Fresnel Edge Sheen (Glass catches reflections on curved boundaries)
                float NdotV = saturate(dot(normalWS, viewDirWS));
                float fresnel = pow(1.0 - NdotV, 4.0) * _FresnelStrength;

                // Combine specular glint and edge glass reflection
                finalRgb += float3(1.0, 1.0, 1.0) * (specular + fresnel);

                return half4(finalRgb, texColor.a);
            }
            ENDHLSL
        }
    }
}