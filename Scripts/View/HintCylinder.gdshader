// The idle hint's look for cylinders (drums): unlit vertical stripes alternating black and the group's color (Tint) round the side, Count of them, and a
// concentric bullseye in the same two colors (rings RingWidth wide) on the top and bottom. The stripe comes from the angle round the
// drum's own axis, so it turns with the piece when the hint spins it.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform int Count = 32;
uniform float RingWidth = 0.077;
uniform vec3 Tint : source_color = vec3(1.0);
varying vec3 Spot;
varying vec3 Facing;

void vertex() {
	Spot = VERTEX;
	Facing = NORMAL;
}

void fragment() {
	float Shade;
	if (abs(Facing.y) > 0.9) {
		Shade = mod(floor(length(Spot.xz) / RingWidth), 2.0);
	} else {
		float Turn = atan(Spot.x, Spot.z) / TAU + 0.5;
		Shade = mod(floor(Turn * float(Count)), 2.0);
	}
	ALBEDO = Shade * Tint;
}
