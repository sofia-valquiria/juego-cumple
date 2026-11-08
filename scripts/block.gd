extends StaticBody2D
# A solid block that reacts when a player hits it from below, like a Mario ? block.
# Everything (collision, visuals, text) is built in code, so no scene editing is needed.

signal pressed(block, player)   # Sent the first time someone hits it

const WIDTH := 48.0    # Block width in pixels; change this to make it wider or narrower
const HEIGHT := 18.0   # Block height in pixels
const DEPTH := Vector2(4, 4)   # How far the back block sticks out to the lower right; bigger = deeper
const FONT_PATH := "res://fonts/PressStart2P-Regular.ttf"   # Where you saved the pixel font
const LABEL_SIZE := Vector2(96, 12)   # Fixed label box; the text is centered inside it

var label_text := ""   # Type name shown as the block's text
var color := Color.WHITE   # Block color when unused
var text_color := Color.WHITE   # Color of the text
var text_color_idx := -1   # Which palette entry main.gd last used (-1 = none yet)
var text_offset := Vector2(0, -HEIGHT / 2.0 - 8.0)   # Center of the text relative to the block center; default is just above it
var first_presser = null   # Who hit it first, null until someone does
var _box: ColorRect   # The front face of the block
var _label: Label   # The text
var _bumping := false   # True during the bounce animation, to avoid stacking tweens


# Called by main.gd right after creating the block, before it enters the tree
func setup(text: String, c: Color, tc: Color = Color.WHITE):
	label_text = text   # Remember the name
	color = c   # Remember the block color
	text_color = tc   # Remember the text color


func _ready():
	collision_layer = 1   # Solid for players, same layer as the level
	collision_mask = 0   # A static block doesn't need to detect anything

	var shape := CollisionShape2D.new()   # Collision shape built in code
	var rect := RectangleShape2D.new()
	rect.size = Vector2(WIDTH, HEIGHT)   # Collision matches the front face only, not the depth effect
	shape.shape = rect
	add_child(shape)

	# Back block: added first so it is drawn behind the front face
	var back := ColorRect.new()
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE   # Controls block mouse clicks by default; this lets clicks reach main.gd
	back.size = Vector2(WIDTH, HEIGHT)   # Same size as the front, so it looks like a thick block
	back.position = Vector2(-WIDTH / 2, -HEIGHT / 2) + DEPTH   # Shifted down-right so the edge shows
	back.color = color.darkened(0.65)   # Much darker than the front so it reads as shadow and depth
	add_child(back)

	# Front face
	_box = ColorRect.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.size = Vector2(WIDTH, HEIGHT)
	_box.position = Vector2(-WIDTH / 2, -HEIGHT / 2)   # Center it on the body
	_box.color = color
	add_child(_box)

	# Light strip along the top of the front face, like a bevel catching the light
	var shine := ColorRect.new()
	shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shine.size = Vector2(WIDTH, 2)   # 2 pixels tall keeps the pixel-art look
	shine.position = Vector2(-WIDTH / 2, -HEIGHT / 2)
	shine.color = Color(1, 1, 1, 0.35)   # Semi-transparent white so it works on any block color
	add_child(shine)

	# Text with the pixel font
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.text = label_text
	if ResourceLoader.exists(FONT_PATH):   # Only use the font if the file exists, so a wrong path doesn't crash the game
		_label.add_theme_font_override("font", load(FONT_PATH))
	_label.add_theme_font_size_override("font_size", 8)   # Press Start 2P stays sharp at multiples of 8
	_label.add_theme_constant_override("outline_size", 3)   # Dark outline so any text color stays readable
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.size = LABEL_SIZE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER   # Centered text inside its box
	_label.z_index = 1   # Always above the block faces
	add_child(_label)
	set_text_color(text_color)   # Applies the color to the label
	set_text_offset(text_offset)   # Applies the position to the label


# Changes the text color at any time
func set_text_color(c: Color):
	text_color = c
	if _label != null:
		_label.add_theme_color_override("font_color", c)


# Moves the text; o is the center of the text relative to the block center
func set_text_offset(o: Vector2):
	text_offset = o
	if _label != null:
		_label.position = o - LABEL_SIZE / 2.0   # The label's corner is its center minus half its box


# Called by player.gd when a player's head hits the underside
func hit_from_below(player):
	_bump()   # Always animate
	_box.color = color.darkened(0.5)   # Darker color shows the block was hit
	pressed.emit(self, player)   # Every hit is reported; main.gd decides the ranking


func _bump():
	if _bumping:
		return   # Ignore hits while already bouncing
	_bumping = true
	var y0 := position.y   # Resting height
	var t := create_tween()   # Animation helper, dies with the block
	t.tween_property(self, "position:y", y0 - 4, 0.06)   # Jump up a few pixels
	t.tween_property(self, "position:y", y0, 0.08)   # Come back down
	t.tween_callback(func(): _bumping = false)   # Allow the next bump


# Makes the block usable again (main.gd calls this on R)
func reset():
	first_presser = null   # Forget who pressed it
	if _box != null:
		_box.color = color   # Restore the original color
