shader_type canvas_item;

// Crops a square texture into a circle inscribed in it, with a soft
// antialiased edge - used to turn the minimap's live SubViewport render
// into a proper round minimap instead of a square panel.
void fragment() {
	vec2 centered = (UV - vec2(0.5)) * 2.0;
	float dist = length(centered);
	vec4 tex_color = texture(TEXTURE, UV);
	tex_color.a *= 1.0 - smoothstep(0.94, 1.0, dist);
	COLOR = tex_color;
}
