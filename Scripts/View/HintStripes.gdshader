// The idle hint's look for spheres: unlit stripes alternating black and the group's color (Tint) running from pole to pole (lines of longitude), Count of
// them round the sphere, alternating. The stripe is picked from the angle round the sphere's vertical axis, so all stripes
// are the same width at the equator and meet cleanly at the poles.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform int Count = 16;
uniform vec3 Tint : source_color = vec3(1.0);
varying vec3 Spot;

void vertex() {
	Spot = VERTEX;
}

void fragment() {
	float Turn = atan(Spot.x, Spot.z) / TAU + 0.5;
	float Stripe = floor(Turn * float(Count));
	ALBEDO = mod(Stripe, 2.0) * Tint;
}
