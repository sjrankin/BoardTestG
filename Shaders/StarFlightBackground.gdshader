shader_type sky;
// Flying through space: stars drift out from the middle of the screen, growing and brightening as they come near, slowly.
// Each layer is a grid of stars at its own depth; a layer's depth runs from far to near and starts again with new stars.

uniform float Aspect = 1.78;
uniform float Speed = 0.045;

vec2 Hash2(vec2 P)
{
	vec3 Q = fract(vec3(P.xyx) * vec3(0.1031, 0.1030, 0.0973));
	Q += dot(Q, Q.yzx + 33.33);
	return fract((Q.xx + Q.yz) * Q.zy);
}

void sky()
{
	if (AT_CUBEMAP_PASS)
	{
		COLOR = vec3(0.01, 0.012, 0.03);
	}
	else
	{
		vec3 Color = vec3(0.004, 0.006, 0.02);
		vec2 Centered = (SCREEN_UV - 0.5) * vec2(Aspect, 1.0);
		const int Layers = 10;
		for (int Layer = 0; Layer < Layers; Layer++)
		{
			float Phase = float(Layer) / float(Layers) + TIME * Speed;
			float Depth = fract(Phase);
			float Round = floor(Phase);
			// Far layers show many tiny stars; near ones few, big, and spread apart (the grid is stretched by the scale).
			float Scale = mix(18.0, 1.2, Depth * Depth);
			vec2 Grid = Centered * Scale + vec2(float(Layer) * 13.7 + Round * 5.3, float(Layer) * 7.1 - Round * 2.9);
			vec2 Cell = floor(Grid);
			vec2 Local = fract(Grid) - 0.5;
			vec2 Random = Hash2(Cell + float(Layer) * 19.0 + Round * 3.0);
			if (Random.x > 0.78)
			{
				vec2 Place = (Random - 0.5) * 0.7;
				float Size = mix(0.03, 0.06, Depth) * (0.7 + Random.y * 0.6);
				float Dot = pow(smoothstep(Size, 0.0, length(Local - Place)), 1.5);
				// New stars fade in from far away and fade out as they pass.
				float Fade = smoothstep(0.0, 0.15, Depth) * smoothstep(1.0, 0.85, Depth);
				vec3 Tint = mix(vec3(0.7, 0.82, 1.0), vec3(1.0, 0.9, 0.78), Random.y);
				Color += Tint * Dot * Fade * mix(0.5, 1.0, Depth);
			}
		}
		COLOR = Color;
	}
}
