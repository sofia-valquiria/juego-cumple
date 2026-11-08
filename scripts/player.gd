extends CharacterBody2D
# Platformer player with run, jump, double jump, dash and wall moves.
# Input comes from self.device, so every copy of this node reads its own controls.

@export_group("Run")
@export var speed: float = 130.0
@export var acceleration: float = 1300.0
@export var friction: float = 1600.0

@export_group("Jump")
@export var jump_velocity: float = -300.0
@export var double_jump_velocity: float = -260.0
@export var jump_cut: float = 0.45
@export var max_air_jumps: int = 1

@export_group("Dash")
@export var dash_speed: float = 340.0
@export var dash_duration: float = 0.14
@export var dash_cooldown: float = 0.35

@export_group("Wall")
@export var wall_slide_speed: float = 55.0
@export var wall_jump_velocity: float = -300.0
@export var wall_jump_push: float = 170.0
@export var wall_jump_lock: float = 0.12

@export_group("Forgiveness")
@export var coyote_time: float = 0.10
@export var jump_buffer: float = 0.10

var base_gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
@export_group("Gravity")
@export var rise_gravity_mult: float = 0.9
@export var fall_gravity_mult: float = 1.5
@export var max_fall_speed: float = 400.0
@export var apex_speed_threshold: float = 45.0
@export var apex_gravity_mult: float = 0.55
@export_group("")

@export var push_ratio: float = 0.6   # Pushed players move at 60% of the pusher's speed, so pushing feels heavy

# --- Input device (set by the level script) ---
# "" = inactive, "kb1"/"kb2" = keyboard sets, "pad0" = whole controller,
# "pad0L"/"pad0R" = one controller shared by two players (left or right half)
var device := ""

const KEYMAPS := {
	"kb1": {"left": KEY_A, "right": KEY_D, "jump": KEY_W, "dash": KEY_S},          # WASD player
	"kb2": {"left": KEY_LEFT, "right": KEY_RIGHT, "jump": KEY_UP, "dash": KEY_DOWN}, # Arrow keys player
}

var move_dir := 0.0               # Horizontal input this frame, -1 to 1
var jump_pressed_now := false     # True only on the frame jump goes down
var jump_released_now := false    # True only on the frame jump comes up
var dash_pressed_now := false     # True only on the frame dash goes down
var _prev := {}                   # Last frame's button states, used to find presses and releases

# --- Runtime state ---
var coyote_timer = 0.0
var jump_buffer_timer = 0.0
var air_jumps_left = 0
var is_dashing = false
var dash_timer = 0.0
var dash_cooldown_timer = 0.0
var can_dash = true
var dash_dir = 1.0
var wall_jump_lock_timer = 0.0
var is_wall_sliding = false
var double_jump_timer = 0.0

@onready var animated_sprite = $AnimatedSprite2D


# Turns "is it held now" into 1 (just pressed), -1 (just released) or 0
func _edge(id: String, now: bool) -> int:
	var before: bool = _prev.get(id, false)   # Was it held on the previous frame?
	_prev[id] = now                           # Store it so the next frame can compare
	if now and not before:
		return 1
	if before and not now:
		return -1
	return 0


# ---------------------------------------------------------------------------
# CONTROLLER LAYOUT: edit these lists to remap buttons.
# Godot names buttons by POSITION, not by label:
#   JOY_BUTTON_A = bottom face button  = Xbox A  = PlayStation Cross (X)
#   JOY_BUTTON_X = left face button    = Xbox X  = PlayStation Square
# Whole controller (one player): stick or D-pad moves, A / Cross jumps, X / Square dashes.
# One controller shared by two players: each player uses one side.
#   Left player:  left stick moves,  LB or D-pad down jumps (the "A" of the left side), LT or D-pad left dashes
#   Right player: right stick moves, RB or A / Cross jumps,                             RT or X / Square dashes
# ---------------------------------------------------------------------------
const PAD_JUMP := [JOY_BUTTON_A]
const PAD_DASH := [JOY_BUTTON_X]
const LEFT_JUMP := [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_DPAD_DOWN]
const LEFT_DASH := [JOY_BUTTON_DPAD_LEFT]
const RIGHT_JUMP := [JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_A]
const RIGHT_DASH := [JOY_BUTTON_X]


# True if any button in the list is held on controller id
func _any_pressed(id: int, buttons: Array) -> bool:
	for b in buttons:
		if Input.is_joy_button_pressed(id, b):
			return true
	return false


# Reads this player's device once per physics frame and fills the input variables
func _read_inputs():
	var axis := 0.0          # Horizontal value before the deadzone
	var jump_down := false   # Is jump held right now?
	var dash_down := false   # Is dash held right now?

	if device.begins_with("kb"):
		var m: Dictionary = KEYMAPS[device]   # Key layout for this keyboard player
		axis = float(Input.is_physical_key_pressed(m["right"])) - float(Input.is_physical_key_pressed(m["left"]))
		jump_down = Input.is_physical_key_pressed(m["jump"])
		dash_down = Input.is_physical_key_pressed(m["dash"])
	elif device.begins_with("pad"):
		var digits := ""   # Controller number from "pad2", "pad2L" or "pad12R"
		for ch in device.substr(3):
			if ch.is_valid_int():
				digits += ch
			else:
				break
		var id := int(digits)
		var side := device.substr(3 + digits.length())   # "" whole pad, "L" left half, "R" right half
		if side == "L":
			axis = Input.get_joy_axis(id, JOY_AXIS_LEFT_X)   # Left stick only, so the right half is free for the other player
			jump_down = _any_pressed(id, LEFT_JUMP)
			dash_down = _any_pressed(id, LEFT_DASH) or Input.get_joy_axis(id, JOY_AXIS_TRIGGER_LEFT) > 0.5
		elif side == "R":
			axis = Input.get_joy_axis(id, JOY_AXIS_RIGHT_X)   # Right stick only
			jump_down = _any_pressed(id, RIGHT_JUMP)
			dash_down = _any_pressed(id, RIGHT_DASH) or Input.get_joy_axis(id, JOY_AXIS_TRIGGER_RIGHT) > 0.5
		else:
			axis = Input.get_joy_axis(id, JOY_AXIS_LEFT_X)   # Left stick
			if Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_LEFT):
				axis = -1.0   # D-pad left also works
			if Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_RIGHT):
				axis = 1.0   # D-pad right also works
			jump_down = _any_pressed(id, PAD_JUMP)
			dash_down = _any_pressed(id, PAD_DASH)

	move_dir = axis if absf(axis) > 0.25 else 0.0   # Deadzone so stick drift doesn't move the player
	var j := _edge("jump", jump_down)               # Press/release state of jump
	jump_pressed_now = j == 1
	jump_released_now = j == -1
	dash_pressed_now = _edge("dash", dash_down) == 1


func _physics_process(delta):
	_read_inputs()   # Must run first so everything below sees fresh input
	_tick_dash(delta)
	if double_jump_timer > 0.0:
		double_jump_timer -= delta
	if is_dashing:
		_update_animation()
		_move(delta)
		return

	_apply_gravity(delta)
	_handle_wall_slide(delta)
	_handle_jump(delta)
	_handle_horizontal(delta)
	_try_start_dash()
	_update_animation()
	_move(delta)


func _apply_gravity(delta):
	if not is_on_floor():
		var mult = rise_gravity_mult if velocity.y < 0.0 else fall_gravity_mult
		if absf(velocity.y) < apex_speed_threshold:
			mult *= apex_gravity_mult
		velocity.y += base_gravity * mult * delta
		velocity.y = min(velocity.y, max_fall_speed)


func _handle_jump(delta):
	if is_on_floor():
		coyote_timer = coyote_time
		air_jumps_left = max_air_jumps
	else:
		coyote_timer = max(coyote_timer - delta, 0.0)

	if jump_pressed_now:
		jump_buffer_timer = jump_buffer
	else:
		jump_buffer_timer = max(jump_buffer_timer - delta, 0.0)

	if jump_buffer_timer > 0.0 and is_on_wall_only() and not is_on_floor():
		_do_wall_jump()
		jump_buffer_timer = 0.0
	elif jump_buffer_timer > 0.0 and coyote_timer > 0.0:
		velocity.y = jump_velocity
		jump_buffer_timer = 0.0
		coyote_timer = 0.0
	elif jump_buffer_timer > 0.0 and air_jumps_left > 0:
		velocity.y = double_jump_velocity
		air_jumps_left -= 1
		double_jump_timer = 0.45
		jump_buffer_timer = 0.0

	if jump_released_now and velocity.y < 0.0:
		velocity.y *= jump_cut


func _do_wall_jump():
	var wall_normal = get_wall_normal()
	velocity.x = wall_normal.x * wall_jump_push
	velocity.y = wall_jump_velocity
	wall_jump_lock_timer = wall_jump_lock
	air_jumps_left = max_air_jumps
	can_dash = true
	animated_sprite.flip_h = wall_normal.x > 0.0


func _handle_wall_slide(_delta):
	is_wall_sliding = false
	if is_on_floor() or not is_on_wall_only() or velocity.y <= 0.0:
		return
	var wall_normal = get_wall_normal()
	if move_dir != 0.0 and signf(move_dir) == -signf(wall_normal.x):
		velocity.y = minf(velocity.y, wall_slide_speed)
		is_wall_sliding = true
		animated_sprite.flip_h = wall_normal.x < 0.0


func _tick_dash(delta):
	if dash_cooldown_timer > 0.0:
		dash_cooldown_timer -= delta
	if is_dashing:
		dash_timer -= delta
		velocity.x = dash_dir * dash_speed
		velocity.y = 0.0
		if dash_timer <= 0.0:
			is_dashing = false
			velocity.x = dash_dir * speed
	if is_on_floor():
		can_dash = true


func _try_start_dash():
	if not dash_pressed_now:
		return
	if is_dashing or not can_dash or dash_cooldown_timer > 0.0:
		return
	dash_dir = signf(move_dir) if move_dir != 0.0 else (1.0 if animated_sprite.flip_h else -1.0)
	is_dashing = true
	dash_timer = dash_duration
	dash_cooldown_timer = dash_cooldown
	can_dash = false
	animated_sprite.flip_h = dash_dir > 0.0


func _handle_horizontal(delta):
	if wall_jump_lock_timer > 0.0:
		wall_jump_lock_timer -= delta
		animated_sprite.flip_h = velocity.x > 0.0
		return
	if move_dir != 0.0:
		var accel = acceleration if is_on_floor() else acceleration * 0.7
		velocity.x = move_toward(velocity.x, move_dir * speed, accel * delta)
		animated_sprite.flip_h = move_dir > 0.0
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)


func _update_animation():
	if is_wall_sliding:
		animated_sprite.play("wall_jump")
	elif not is_on_floor():
		if double_jump_timer > 0.0:
			animated_sprite.play("double_jump")
		elif velocity.y < 0.0:
			animated_sprite.play("jump")
		else:
			animated_sprite.play("fall")
	elif abs(velocity.x) > 10.0:
		animated_sprite.play("run")
	else:
		animated_sprite.play("idle")
# Replaces move_and_slide(): moves, then pushes other players and bumps blocks
func _move(delta):
	var pre_vx := velocity.x   # Speed before the collision zeroes it, needed to know how hard to push
	move_and_slide()   # Normal movement and collision against walls, floors and other players
	for i in get_slide_collision_count():   # Look at everything we touched this frame
		var c := get_slide_collision(i)   # Details of one collision
		var other = c.get_collider()   # The body we hit
		var n := c.get_normal()   # Direction the surface faces, points away from what we hit
		if other is CharacterBody2D:   # Hit another player
			# Pico Park push: only a sideways hit while walking into them (not standing on their head)
			if absf(n.x) > 0.7 and signf(pre_vx) == -signf(n.x):
				other.move_and_collide(Vector2(pre_vx * delta * push_ratio, 0))   # Shove them along, stopping if they hit a wall
		elif n.y > 0.7 and other.has_method("hit_from_below"):   # We hit something's underside (our head)
			other.hit_from_below(self)   # Tell the block who hit it; checked here because velocity.y is already zeroed by now
