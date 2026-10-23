shader_type sky;
// A blue sky with slowly drifting, fluffy clouds. Drawn in screen space (the same whichever way the camera looks), so the
// whole window shows sky, not just the sliver above the horizon.

uniform float Aspect = 1.78;

float Hash(vec2 P)
{
	P = fract(P * vec2(123.34, 456.21));
	P += dot(P, P + 45.32);
	return fract(P.x * P.y);
}

float Noise(vec2 P)
{
	vec2 I = floor(P);
	vec2 F = fract(P);
	F = F * F * (3.0 - 2.0 * F);
	return mix(mix(Hash(I), Hash(I + vec2(1.0, 0.0)), F.x), mix(Hash(I + vec2(0.0, 1.0)), Hash(I + vec2(1.0, 1.0)), F.x), F.y);
}

float Fbm(vec2 P)
{
	float Sum = 0.0;
	float Amplitude = 0.5;
	for (int Octave = 0; Octave < 5; Octave++)
	{
		Sum += Amplitude * Noise(P);
		P = P * 2.03 + vec2(17.1, 9.7);
		Amplitude *= 0.5;
	}
	return Sum;
}

void sky()
{
	vec3 Top = vec3(0.12, 0.40, 0.88);
	vec3 Low = vec3(0.60, 0.82, 0.98);
	if (AT_CUBEMAP_PASS)
	{
		// What glossy pieces reflect: just the gradient.
		COLOR = mix(Low, Top, clamp(EYEDIR.y * 0.5 + 0.5, 0.0, 1.0));
	}
	else
	{
		vec2 UV = SCREEN_UV;
		vec3 Color = mix(Top, Low, pow(UV.y, 1.3));
		// Clouds get a little bigger toward the top of the screen and drift sideways.
		vec2 P = vec2(UV.x * Aspect, UV.y) * 2.6 + vec2(TIME * 0.1125, TIME * 0.0075);
		float Density = Fbm(P);
		// The same cloud looked at from a little toward the sun: where it is thinner there, it is lit.
		float Toward = Fbm(P + vec2(-0.06, -0.09));
		float Cover = smoothstep(0.46, 0.74, Density);
		float Lit = clamp(0.62 + (Density - Toward) * 5.0, 0.0, 1.0);
		vec3 Cloud = mix(vec3(0.66, 0.73, 0.86), vec3(1.0), Lit);
		Color = mix(Color, Cloud, Cover);
		COLOR = Color;
	}
}
