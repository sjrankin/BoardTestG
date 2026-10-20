// The idle hint's checkerboard for curved pieces: unlit, and black or white by the parity of the cell of a grid of cubes
// (CellSize across, in the piece's own space) that each point is in - so the squares are the same size everywhere, with no
// bunching at the poles or stretching that a picture wrapped round a sphere has.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform float CellSize = 0.2;
varying vec3 Spot;

void vertex() {
	Spot = VERTEX;
}

void fragment() {
	vec3 Cell = floor(Spot / CellSize + vec3(0.001));
	float Shade = mod(Cell.x + Cell.y + Cell.z, 2.0);
	ALBEDO = vec3(Shade);
}
