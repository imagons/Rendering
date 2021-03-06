// 导入代码片段
// #include "UnityCG.cginc"
// 光照相关的功能
// #include "UnityStandardBRDF.cginc"
// 负责能量守恒
// #include "UnityStandardUtils.cginc"
//光照技术
#include "AutoLight.cginc"
// 避免重定义错误
// #if !defined(MY_LIGHTING_INCLUDED)
// #define MY_LIGHTING_INCLUDED
// // PBS 物理规则渲染
#include "UnityPBSLighting.cginc"
// #endif



// 最上面定义了属性之后 我们还需要访问属性
float4 _Tint;
sampler2D _MainTex;
float4 _MainTex_ST; //ST表示缩放和平移
float4 _SpecularTint;
float _Metallic;
float _Smoothness;

struct Interpolators {
    // 四个浮点数的集合 用来弄矩阵的 SV_POSITION是语义 SV表示系统值 POSITION表示最终顶点位置 告诉图形处理器 我们尝试输出顶点的位置
    float4 position : SV_POSITION;
    // 出于什么目的使用TEXCOORD0还待考究
    float2 uv : TEXCOORD0;
    // 法线
    float3 normal : TEXCOORD1;
    // 世界坐标 用来表示观察者方向
    float3 worldPos : TEXCOORD2;
    // 顶点光源
    #if defined(VERTEXLIGHT_ON)
        float3 vertexLightColor : TEXCOORD3;
    #endif
};

struct VertexData {
    float4 position : POSITION;
    // 法线
    float3 normal : NORMAL;
    float2 uv : TEXCOORD0;
};

// inout是从内插值器里面读取和写入结果
void ComputeVertexLightColor(inout Interpolators i) {
    #if defined(VERTEXLIGHT_ON)
        // 4光源位置unity_4LightPosX0
        // float3 lightPos = float3(
        //     unity_4LightPosX0.x, unity_4LightPosY0.x, unity_4LightPosZ0.x
        // );
        // float3 lightVec = lightPos - i.worldPos;
        // float3 lightDir = normalize(lightVec);
        // float ndotl = DotClamped(i.normal, lightDir);
        // float attenuation = 1 / (1 + dot(lightVec, lightVec) * unity_4LightAtten0.x);
        // i.vertexLightColor = unity_LightColor[0].rgb * ndotl * attenuation;
        i.vertexLightColor = Shade4PointLights(
            unity_4LightPosX0, unity_4LightPosY0, unity_4LightPosZ0,
            unity_LightColor[0].rgb, unity_LightColor[1].rgb, 
            unity_LightColor[2].rgb, unity_LightColor[3].rgb, 
            unity_4LightAtten0, i.worldPos, i.normal
        );
    #endif
}

Interpolators MyVertexProgram(VertexData v) {
    Interpolators i;
    // i.uv = v.uv * _MainTex_ST.xy + _MainTex_ST.zw;
    // 这个方法就是用来缩放和平移uv的
    i.uv = TRANSFORM_TEX(v.uv, _MainTex);
    // mul 乘法指令
    // UNITY_MATRIX_MVP是UnityCG里面的UnityShaderVariables 专门用来将顶点正确的投影到显示器上去的
    // 会被Unity升级为UnityObjectToClipPos
    i.position = UnityObjectToClipPos(v.position);
    i.worldPos = mul(unity_ObjectToWorld, v.position);
    // unity_ObjectToWorld 将数据转换到世界坐标空间中 第四个分量必须为零
    // transpose 是转矩阵的意思
    // i.normal = mul(transpose((float3x3)unity_ObjectToWorld), v.normal);
    i.normal = UnityObjectToWorldNormal(v.normal);
    i.normal = normalize(i.normal);
    ComputeVertexLightColor(i);
    return i;
}

// 光源函数
UnityLight CreateLight(Interpolators i) {
    UnityLight light;
    #if defined(POINT) || defined(POINT_COOKIE) || defined(SPOT)
        light.dir = normalize(_WorldSpaceLightPos0.xyz - i.worldPos);
    #else
        light.dir = _WorldSpaceLightPos0.xyz;
    #endif
    // float3 lightVec = _WorldSpaceLightPos0.xyz - i.worldPos;
    // float attenuation = 1 / ( 1 + dot(lightVec, lightVec));
    UNITY_LIGHT_ATTENUATION(attenuation, 0, i.worldPos);
    light.color = _LightColor0.rgb * attenuation;
    light.ndotl = DotClamped(i.normal, light.dir);
    return light;
}

// 间接光原函数
UnityIndirect CreateIndirectLight (Interpolators i) {
    UnityIndirect indirectLight;
    indirectLight.diffuse = 0;
    indirectLight.specular = 0;
    #if defined(VERTEXLIGHT_ON)
        indirectLight.diffuse = i.vertexLightColor;
    #endif
    #if defined(FORWARD_BASE_PASS)
        indirectLight.diffuse += max(0, ShadeSH9(float4(i.normal, 1)));
    #endif
    return indirectLight;
}

// 这个主要用来输出一个RGBA颜色值 默认着色器目标 也就是帧缓冲区 包含我们正在生成的图像
// 需要接收输入 输入就是顶点程序产生的值
float4 MyFragmentProgram(Interpolators i) : SV_TARGET {
    // return float4(i.localPosition + 0.5, 1) * _Tint;
    // return float4(i.uv, 1, 1);
    i.normal = normalize(i.normal);
    // return float4(i.normal * 0.5 + 0.5, 1);
    // 加入垂直光源
    // 不能有负光 所以加入max
    // float3 lightDir      = _WorldSpaceLightPos0.xyz;
    // 视角方向
    float3 viewDir       = normalize(_WorldSpaceCameraPos - i.worldPos);
    // float3 lightColor    = _LightColor0.rgb;
    // 反照率
    float3 albedo        = tex2D(_MainTex, i.uv).rgb * _Tint.rgb;
    // albedo *= 1 - max(_SpecularTint.r, max(_SpecularTint.g, _SpecularTint.b));
    float3 specularTint; // = albedo * _Metallic;
    // 1 减去反射率
    float oneMinusReflectivity; // = 1 - _Metallic;
    // albedo = EnergyConservationBetweenDiffuseAndSpecular(
    //     albedo, _SpecularTint.rgb, oneMinusReflectivity
    // );
    // albedo *= oneMinusReflectivity;
    albedo = DiffuseAndSpecularFromMetallic(
        albedo, _Metallic, specularTint, oneMinusReflectivity
    );

    // float3 diffuse       = albedo * lightColor * DotClamped(lightDir, i.normal);
    // // 反射光方向
    // // float3 reflectionDir = reflect(-lightDir, i.normal);
    // // 入射光和视角的半矢量
    // float3 halfVector = normalize(lightDir + viewDir);
    // float3 specular = specularTint * lightColor * pow(
    //     DotClamped(halfVector, i.normal),
    //     _Smoothness * 100
    // );
    // return float4(diffuse + specular, 1);

    // 直接光
    // UnityLight light;
    // light.color = lightColor;
    // light.dir = lightDir;
    // light.ndotl = DotClamped(i.normal, lightDir);
    // 间接光
    // UnityIndirect indirectLight;
    // indirectLight.diffuse = 0;
    // indirectLight.specular = 0;

    // float3 shColor = ShadeSH9(float4(i.normal, 1));
    // return float4(shColor, 1);

    return UNITY_BRDF_PBS(
        albedo, specularTint,
        oneMinusReflectivity, _Smoothness,
        i.normal, viewDir,
        CreateLight(i), CreateIndirectLight(i)
    );
}