shader_type sky;
// A dark blue night with three layers of stars that twinkle slowly. Drawn in screen space.

uniform float Aspect = 1.78;

vec2 Hash2(vec2 P)
{
	vec3 Q = fract(vec3(P.xyx) * vec3(0.1031, 0.1030, 0.0973));
	Q += dot(Q, Q.yzx + 33.33);
	return fract((Q.xx + Q.yz) * Q.zy);
}

void sky()
{
	vec3 Top = vec3(0.005, 0.012, 0.05);
	vec3 Low = vec3(0.035, 0.05, 0.14);
	if (AT_CUBEMAP_PASS)
	{
		COLOR = mix(Low, Top, clamp(EYEDIR.y * 0.5 + 0.5, 0.0, 1.0)) * 0.6;
	}
	else
	{
		vec3 Color = mix(Top, Low, pow(SCREEN_UV.y, 2.0));
		for (int Layer = 0; Layer < 3; Layer++)
		{
			float Density = 14.0 + float(Layer) * 16.0;
			vec2 Grid = vec2(SCREEN_UV.x * Aspect, SCREEN_UV.y) * Density + float(Layer) * 31.7;
			vec2 Cell = floor(Grid);
			vec2 Local = fract(Grid) - 0.5;
			vec2 Random = Hash2(Cell);
			vec2 Other = Hash2(Cell + 71.3);
			if (Random.x > 0.55)
			{
				vec2 Place = (Random - 0.5) * 0.6;
				float Size = mix(0.045, 0.018, float(Layer) / 2.0) * (0.6 + Other.x * 0.8);
				float Dot = pow(smoothstep(Size, 0.0, length(Local - Place)), 1.5);
				// Each star has its own slow rhythm, between about 4 and 12 seconds a swell.
				float Twinkle = 0.55 + 0.45 * sin(TIME * (0.5 + Other.x * 1.0) + Other.y * 6.2832);
				vec3 Tint = mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.92, 0.8), Other.y);
				Color += Tint * Dot * Twinkle * (0.5 + Random.y * 0.5);
			}
		}
		COLOR = Color;
	}
}
