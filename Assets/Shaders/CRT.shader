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
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

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
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                return OUT;
            }

            // Stable UV-space Phosphor Triad Mask for a 640x480 NTSC grid
            float3 GetPhosphorMask(float2 uv)
            {
                // Map UV.x to a virtual 640-pixel horizontal resolution width
                float xCoord = uv.x * 640.0 / _MaskSize;
                int columnIndex = (int)fmod(floor(xCoord), 3.0);

                // Instead of absolute black (0.0) which crushes colors and tints the image red,
                // we use a gentle attenuation so subpixels dip rather than die entirely.
                float3 mask;
                if (columnIndex == 0)
                    mask = float3(1.0, 0.2, 0.2); // Red column active
                else if (columnIndex == 1)
                    mask = float3(0.2, 1.0, 0.2); // Green column active
                else
                    mask = float3(0.2, 0.2, 1.0); // Blue column active

                return mask;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                // 1. Sample base texture
                half4 texColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;

                // 2. Scanlines Effect
                float scanline = sin(IN.uv.y * _ScanlineCount * 3.14159265 * 2.0);
                scanline = scanline * 0.5 + 0.5;
                float3 scanlineColor = texColor.rgb * lerp(1.0, scanline, _ScanlineIntensity);

                // 3. Phosphor Triads (Shadow Mask) using local UV coordinates
                float3 mask = GetPhosphorMask(IN.uv);
                // Blend mask smoothly without overpowering the source video colors
                float3 maskedColor = lerp(scanlineColor, scanlineColor * mask, _MaskStrength);

                // 4. Rounded Rectangle Vignette
                float2 uvCenter = IN.uv - 0.5;
                float2 halfSize = float2(_VignetteLength, _VignetteHeight);
                float2 d = abs(uvCenter) - (halfSize - _VignetteRoundness);
                float dist = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - _VignetteRoundness;
                float vignetteFactor = saturate(dist * _VignetteIntensity * 10.0);
                
                half3 finalRgb = lerp(maskedColor, 0.0, vignetteFactor);

                return half4(finalRgb, texColor.a);
            }
            ENDHLSL
        }
    }
}