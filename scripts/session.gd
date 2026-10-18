class_name Session
extends RefCounted
## What survives a scene reload. Starting, restarting and returning to the menu reload the
## game scene (so the XR rig, camera and mode set up cleanly); this carries the request across.

static var pending: GameConfig = null      # a game to start as soon as the scene loads
static var current: GameConfig = null      # the game being played, for Restart
static var show_menu := false              # open the main menu when the scene loads
