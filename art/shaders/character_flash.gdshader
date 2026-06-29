shader_type canvas_item;

// Per-pixel flash feedback on the art rig, alpha preserved. Two independent channels:
//   invert_amount - flash toward the sprite's INVERSE colors (hit feedback).
//   flash_amount  - flash toward flash_color, default white (projectile-charge feedback).
uniform float invert_amount : hint_range(0.0, 1.0) = 0.0;
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec3 c = mix(tex.rgb, vec3(1.0) - tex.rgb, invert_amount);
	c = mix(c, flash_color.rgb, flash_amount);
	COLOR = vec4(c, tex.a);
}
