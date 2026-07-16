class_name ThemeFactory
extends RefCounted

const TOKENS := {
	"ink": Color("21302d"),
	"paper": Color("f4f1e8"),
	"mist": Color("dbe5df"),
	"willow": Color("6e8b63"),
	"wood": Color("8a6747"),
	"seal": Color("a93d35"),
	"water": Color("5f8991"),
	"warning": Color("b56a2d"),
}


func get_tokens() -> Dictionary:
	return TOKENS.duplicate()


func create_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 16

	theme.set_color("font_color", "Label", TOKENS["ink"])
	theme.set_color("font_color", "Button", TOKENS["paper"])
	theme.set_color("font_hover_color", "Button", TOKENS["paper"])
	theme.set_color("font_pressed_color", "Button", TOKENS["paper"])
	theme.set_color("font_focus_color", "Button", TOKENS["paper"])
	theme.set_color("font_disabled_color", "Button", Color("7f8a86"))
	theme.set_color("font_color", "LineEdit", TOKENS["ink"])
	theme.set_color("font_color", "TextEdit", TOKENS["ink"])
	theme.set_color("font_color", "ItemList", TOKENS["ink"])
	theme.set_color("font_selected_color", "ItemList", TOKENS["paper"])
	theme.set_color("font_hovered_color", "ItemList", TOKENS["ink"])
	theme.set_color("font_placeholder_color", "LineEdit", Color("6f7975"))
	theme.set_color("font_placeholder_color", "TextEdit", Color("6f7975"))
	theme.set_color("caret_color", "LineEdit", TOKENS["seal"])
	theme.set_color("caret_color", "TextEdit", TOKENS["seal"])
	theme.set_color("selection_color", "LineEdit", Color("b9d0cc"))
	theme.set_color("selection_color", "TextEdit", Color("b9d0cc"))

	theme.set_stylebox(
		"panel",
		"PanelContainer",
		_style_box(TOKENS["paper"], TOKENS["ink"], 1, 6),
	)
	theme.set_stylebox(
		"normal",
		"Button",
		_style_box(TOKENS["water"], TOKENS["ink"], 1, 4),
	)
	theme.set_stylebox(
		"hover",
		"Button",
		_style_box(Color("4c747c"), TOKENS["ink"], 1, 4),
	)
	theme.set_stylebox(
		"pressed",
		"Button",
		_style_box(Color("3e6067"), TOKENS["ink"], 1, 4),
	)
	theme.set_stylebox(
		"focus",
		"Button",
		_style_box(Color.TRANSPARENT, TOKENS["seal"], 3, 4),
	)
	theme.set_stylebox(
		"disabled",
		"Button",
		_style_box(Color("c8cfcb"), Color("9aa39f"), 1, 4),
	)

	var field_normal := _style_box(Color("fffdf7"), Color("82918b"), 1, 4)
	var field_focus := _style_box(Color("fffdf7"), TOKENS["water"], 2, 4)
	for control_type in ["LineEdit", "TextEdit"]:
		theme.set_stylebox("normal", control_type, field_normal)
		theme.set_stylebox("focus", control_type, field_focus)
		theme.set_stylebox("read_only", control_type, field_normal)

	theme.set_stylebox(
		"normal",
		"ItemList",
		_style_box(Color("fffdf7"), Color("82918b"), 1, 4),
	)
	theme.set_stylebox(
		"focus",
		"ItemList",
		_style_box(Color.TRANSPARENT, TOKENS["water"], 2, 4),
	)
	theme.set_stylebox(
		"selected",
		"ItemList",
		_style_box(TOKENS["water"], TOKENS["water"], 0, 3),
	)
	theme.set_stylebox(
		"selected_focus",
		"ItemList",
		_style_box(TOKENS["water"], TOKENS["seal"], 2, 3),
	)
	theme.set_constant("line_separation", "Label", 4)
	theme.set_constant("outline_size", "Label", 0)
	return theme


func contrast_ratio(first: Color, second: Color) -> float:
	var first_luminance := _relative_luminance(first)
	var second_luminance := _relative_luminance(second)
	var lighter := maxf(first_luminance, second_luminance)
	var darker := minf(first_luminance, second_luminance)
	return (lighter + 0.05) / (darker + 0.05)


func _style_box(
	background: Color,
	border: Color,
	border_width: int,
	corner_radius: int,
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	style.content_margin_left = 12.0
	style.content_margin_top = 8.0
	style.content_margin_right = 12.0
	style.content_margin_bottom = 8.0
	return style


func _relative_luminance(color: Color) -> float:
	return (
		0.2126 * _linear_channel(color.r)
		+ 0.7152 * _linear_channel(color.g)
		+ 0.0722 * _linear_channel(color.b)
	)


func _linear_channel(value: float) -> float:
	if value <= 0.04045:
		return value / 12.92
	return pow((value + 0.055) / 1.055, 2.4)
