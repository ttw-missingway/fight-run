shader_type canvas_item;

// Lerps the sprite toward flash_color by flash_amount, preserving alpha.
// Used by Fighter for hit and projectile-charge white-flash feedback on the art rig.
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(mix(tex.rgb, flash_color.rgb, flash_amount), tex.a);
}
