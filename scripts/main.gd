extends Node2D
## Buzzer level: up to 4 local players, a shared camera and 4 fixed buttons (blocks).
##   F1 = keyboard players: 2 (WASD + arrows) -> 1 (WASD) -> 0 (controllers only) -> 2
##   F2 = shared controllers: ON = each controller holds two players, OFF = one player per controller
##   R  = respawn everyone + reset buzzers      B = reset buzzers only (nobody moves)

@onready var player = $Player            # The player already in your scene becomes player 1

const FALL_LIMIT := 300.0                # Below this Y a player falls out of the level
const CAMERA_OFFSET := Vector2(0, -30)   # Camera looks slightly above the players' feet
const MAX_PLAYERS := 4                   # How many players exist at most
const SKINS := [
	preload("res://assets/kenney_pixel-platformer/Tiles/Characters/hada.tres"),
	preload("res://assets/kenney_pixel-platformer/Tiles/Characters/veneno.tres"),
	preload("res://assets/kenney_pixel-platformer/Tiles/Characters/psiquico.tres"),
	preload("res://assets/kenney_pixel-platformer/Tiles/Characters/oscuro.tres"),
]
const HitBlock := preload("res://scripts/block.gd")   # The block script, loaded once
const TYPES := ["Hada", "Veneno", "Psíquico", "Oscuro"]   # Block i belongs to player (i % 4)
const TYPE_COLORS := [Color("ff9ad5"), Color("9b4fd0"), Color("f8507a"), Color("4a4040")]   # Pink, purple, red-pink, dark
const OWN_BLOCK_ONLY := false   # true = a player only counts when hitting the block of their own type
const SHOW_BLOCK_NAMES := true   # false hides the small name above each block
const FONT_PATH := "res://fonts/PressStart2P-Regular.ttf"   # Pixel font for the ranking

# Final, fixed positions of the buttons: Hada, Veneno, Psíquico, Oscuro
@export var block_positions: Array[Vector2] = [Vector2(70, -72), Vector2(144, -72), Vector2(240, -72), Vector2(320, -72)]

@export var default_text_color: Color = Color.WHITE   # Color of the names above the blocks

@export var popup_color: Color = Color.YELLOW:   # Color of the ranking text
	set(value):
		popup_color = value
		_apply_popup_style()

@export var popup_offset: Vector2 = Vector2(0, 60):   # Ranking position: x sideways, y distance from the top
	set(value):
		popup_offset = value
		_apply_popup_style()

var ranking: Array = []   # Players in the order they pressed a button (each only once)
var blocks: Array = []   # The block nodes
var keyboard_players := 2   # 2, 1 or 0 keyboard players (F1)
var shared_pads := false   # True = each controller becomes two players (F2)
var players: Array = []   # All four player nodes
var _spawns := {}   # Start position per player
var _layers := {}   # Original collision layer per player
var _masks := {}   # Original collision mask per player
var _popup: Label   # The ranking text, the only text on screen
var _popup_tween: Tween


func _ready():
	players.append(player)   # Player 1 is the node from the scene
	for i in range(1, MAX_PLAYERS):
		var p = player.duplicate()   # Copy of player 1, including script and settings
		p.position = player.position + Vector2(30 * i, 0)   # Offset so they don't start inside each other
		add_child(p)
		players.append(p)

	for i in MAX_PLAYERS:
		var p = players[i]
		_spawns[p] = p.position   # Remember where this player starts
		p.collision_layer = 2   # Players live on layer 2
		p.collision_mask = 3   # They collide with layer 1 (level, blocks) and layer 2 (players)
		_layers[p] = p.collision_layer
		_masks[p] = p.collision_mask
		var spr: AnimatedSprite2D = p.get_node("AnimatedSprite2D")
		spr.sprite_frames = SKINS[i]   # Own art per player
		spr.modulate = Color.WHITE
		spr.play("idle")

	var layer := CanvasLayer.new()   # Screen-space layer for the ranking
	add_child(layer)
	_popup = Label.new()
	_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_popup.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_popup.add_theme_font_size_override("font_size", 16)
	_popup.add_theme_constant_override("outline_size", 4)
	_popup.add_theme_color_override("font_outline_color", Color.BLACK)
	if ResourceLoader.exists(FONT_PATH):
		_popup.add_theme_font_override("font", load(FONT_PATH))
	_popup.visible = false   # Hidden until someone presses a button
	layer.add_child(_popup)
	_apply_popup_style()

	for i in block_positions.size():   # Create the fixed buttons
		var b = HitBlock.new()
		b.setup(TYPES[i % TYPES.size()], TYPE_COLORS[i % TYPES.size()], default_text_color)
		b.z_index = 10   # Draw above the level
		b.pressed.connect(_on_block_pressed)
		add_child(b)
		b.position = block_positions[i]
		b._label.visible = SHOW_BLOCK_NAMES
		blocks.append(b)

	Input.joy_connection_changed.connect(func(_id, _connected): _assign_devices())   # Reassign when pads connect or disconnect
	_assign_devices()


# Builds the device list from the toggles and hands one to each player
func _assign_devices():
	var devices: Array = []
	if keyboard_players >= 1:
		devices.append("kb1")   # WASD player
	if keyboard_players >= 2:
		devices.append("kb2")   # Arrow keys player
	for id in Input.get_connected_joypads():
		if shared_pads:
			devices.append("pad%dL" % id)   # Left half of this controller
			devices.append("pad%dR" % id)   # Right half of this controller
		else:
			devices.append("pad%d" % id)   # Whole controller, one player

	for i in MAX_PLAYERS:
		var p = players[i]
		var on: bool = i < devices.size()   # Is there a device left for this player?
		p.device = devices[i] if on else ""   # Empty device means inactive
		p.visible = on
		p.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
		p.collision_layer = _layers[p] if on else 0
		p.collision_mask = _masks[p] if on else 0
		_respawn(p)


func _process(_delta):
	var sum := Vector2.ZERO
	var count := 0
	for p in players:
		if p.device == "":
			continue   # Ignore inactive players
		if p.global_position.y > FALL_LIMIT:
			_respawn(p)   # Fell into the gap
		sum += p.global_position
		count += 1
	if count > 0:
		var center := sum / count + CAMERA_OFFSET   # Midpoint of active players
		$Camera2D.global_position = $Camera2D.global_position.lerp(center, 0.15)


func _unhandled_input(event):
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_F1:
			keyboard_players = (keyboard_players + 2) % 3   # 2 -> 1 -> 0 -> 2
			_assign_devices()
		KEY_F2:
			shared_pads = not shared_pads
			_assign_devices()
		KEY_R:
			for p in players:
				_respawn(p)   # Everyone back to start
			_reset_buzzers()
		KEY_B:
			_reset_buzzers()   # New round: nobody moves


func _respawn(p):
	p.global_position = _spawns[p]
	p.velocity = Vector2.ZERO


# Registers a player's press; only their first press counts
func _on_block_pressed(block, p):
	var n := players.find(p)   # Index of the player who hit the block (0 to 3)
	if n < 0 or p in ranking:
		return
	if OWN_BLOCK_ONLY and block.label_text != TYPES[n]:
		return   # Wrong button for this player
	ranking.append(p)
	var m0 := players.find(ranking[0])
	var text := "FIRST: P%d (%s)" % [m0 + 1, TYPES[m0]]   # The winner, always on top
	for i in range(1, ranking.size()):
		var k := players.find(ranking[i])
		text += "\n%d. P%d (%s)" % [i + 1, k + 1, TYPES[k]]   # The rest, in order of arrival
	print(text)
	_popup.text = text
	_popup.visible = true   # Stays until the buzzers are reset


# Clears the ranking and the buttons without touching players or their positions
func _reset_buzzers():
	ranking.clear()
	for b in blocks:
		if is_instance_valid(b):
			b.reset()
	_popup.visible = false


func _apply_popup_style():
	if _popup == null or not _popup.is_inside_tree():
		return
	_popup.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_popup.offset_left = popup_offset.x
	_popup.offset_right = popup_offset.x
	_popup.offset_top = popup_offset.y
	_popup.offset_bottom = popup_offset.y + 160   # Room for the whole ranking
	_popup.add_theme_color_override("font_color", popup_color)
