class_name DriftBar extends MarginContainer

# HUD bar shown at the top-center of the screen: a glass panel with a label and
# SEGMENTS cells that fill up (grey -> blue) while the vehicle keeps drifting.
#
# Drift = the smoke trail is being emitted (Vehicle.is_drifting).
#  - smoke shown      -> counter grows, 1 segment every `seconds_per_segment`
#  - smoke not shown  -> counter freezes, after `reset_delay` seconds it resets to 0
#  - smoke back before the reset -> counter resumes from where it was

const SEGMENTS := 6

@export_group("Properties")
@export var target: Vehicle
@export var seconds_per_segment: float = 1.0
@export var reset_delay: float = 2.0

@export_group("Look")
@export var top_margin: int = 24
@export var panel_texture: Texture2D
@export var panel_color: Color = Color(1, 1, 1, 0.7)
## Size (px) of the panel corners that are not stretched (9-slice)
@export var panel_slice: int = 16
@export var panel_padding: Vector2i = Vector2i(20, 10)
## Texture of an empty segment
@export var segment_off_texture: Texture2D
## Texture of a filled segment
@export var segment_on_texture: Texture2D
@export var segment_size: Vector2 = Vector2(22, 32)
@export var segment_spacing: int = 3
## Leave empty to hide the label
@export var label_text: String = "Drift"
@export var label_font: Font
@export var label_font_size: int = 20
@export var label_color: Color = Color(0.2, 0.24, 0.35)

var drift_time: float = 0.0   # seconds of drift accumulated
var idle_time: float = 0.0    # seconds since the smoke stopped

var segments: Array[TextureRect] = []
var filled_segments: int = -1

func _ready():

	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("margin_top", top_margin)

	# Glass panel, centered at the top of the screen

	var style := StyleBoxTexture.new()
	style.texture = panel_texture
	style.modulate_color = panel_color
	style.set_texture_margin_all(panel_slice)
	style.content_margin_left = panel_padding.x
	style.content_margin_right = panel_padding.x
	style.content_margin_top = panel_padding.y
	style.content_margin_bottom = panel_padding.y

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(content)

	if label_text != "":
		var label := Label.new()
		label.text = label_text
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", label_font_size)
		label.add_theme_color_override("font_color", label_color)
		if label_font != null: label.add_theme_font_override("font", label_font)
		content.add_child(label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", segment_spacing)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(row)

	for i in SEGMENTS:
		var segment := TextureRect.new()
		segment.custom_minimum_size = segment_size
		segment.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		segment.stretch_mode = TextureRect.STRETCH_SCALE
		segment.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(segment)
		segments.append(segment)

	_update_segments(0)

func _process(delta):

	if target == null: return

	if target.is_drifting:
		drift_time += delta
		idle_time = 0.0
	elif drift_time > 0.0:
		idle_time += delta
		if idle_time >= reset_delay:
			drift_time = 0.0
			idle_time = 0.0

	var filled := mini(int(drift_time / seconds_per_segment), SEGMENTS)

	if filled != filled_segments:
		_update_segments(filled)

# Show the first `filled` segments as "on", the others as "off"

func _update_segments(filled: int):

	filled_segments = filled

	for i in SEGMENTS:
		segments[i].texture = segment_on_texture if i < filled else segment_off_texture
