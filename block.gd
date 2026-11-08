extends StaticBody2D
# A solid block that reacts when a player hits it from below, like a Mario ? block.

signal pressed(block, player)   # Sent the first time someone hits it

const SIZE := 18.0   # Block width and height in pixels

var label_text := ""   # Type name shown above the block
var color := Color.WHITE   # Block color when unused
var first_presser = null   # Who hit it first, null until someone does
var _box: ColorRect   # The visible square
var _bumping := false   # True during the bounce animation, to avoid stacking tweens


# Called by main.gd right after creating the block
func setup(text: String, c: Color):
	label_text = text   # Remember the name
	color = c   # Remember the color


func _ready():
	collision_layer = 1   # Solid for players, same layer as the level
	collision_mask = 0   # A static block doesn't need to detect anything
	var shape := CollisionShape2D.new()   # Collision shape built in code, so no scene editing is needed
	var rect := RectangleShape2D.new()
	rect.size = Vector2(SIZE, SIZE)   # Same size as the visual
	shape.shape = rect
	add_child(shape)
	_box = ColorRect.new()   # Simple colored square instead of a sprite
	_box.size = Vector2(SIZE, SIZE)
	_box.position = Vector2(-SIZE / 2, -SIZE / 2)   # Center it on the body
	_box.color = color
	add_child(_box)
	var l := Label.new()   # Name tag above the block
	l.text = label_text
	l.add_theme_font_size_override("font_size", 8)   # Small so it fits over a small block
	l.position = Vector2(-30, -SIZE / 2 - 14)   # Above the block
	l.size = Vector2(60, 12)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER   # Centered over the block
	add_child(l)


# Called by player.gd when a player's head hits the underside
func hit_from_below(player):
	_bump()   # Always animate, even on repeat hits
	if first_presser == null:   # Only the first hit counts
		first_presser = player   # Remember who it was
		_box.color = color.darkened(0.5)   # Darker color shows the block is used
		pressed.emit(self, player)   # Let main.gd show the popup


func _bump():
	if _bumping:
		return   # Ignore hits while already bouncing
	_bumping = true
	var y0 := position.y   # Resting height
	var t := create_tween()   # Animation helper
	t.tween_property(self, "position:y", y0 - 4, 0.06)   # Jump up a few pixels
	t.tween_property(self, "position:y", y0, 0.08)   # Come back down
	t.tween_callback(func(): _bumping = false)   # Allow the next bump


# Makes the block usable again (main.gd calls this on R)
func reset():
	first_presser = null   # Forget who pressed it
	_box.color = color   # Restore the original color
