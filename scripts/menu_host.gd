class_name MenuHost
extends RefCounted
## The glue between the game and its menus (GameMenu / MenuModel): opening the main menu or the pause menu, closing it, the
## controller's menu button, and what each menu event does to the game (start a game, change a setting, leave, quit). The scene
## (`host`) owns the game and the menu node.

var host                                    # the bullpen scene (untyped: its members are reached by name)

var was_in_menu := true
var menu_button_was := false


func build_menu(show_main: bool) -> void:
	host._menu = GameMenu.new()
	host.add_child(host._menu)
	var ctrls: Array[XRController3D] = []
	for c in [host._hand, host._off_hand]:
		if c != null:
			ctrls.append(c)
	var menu_model = MenuModel.new(host._settings)
	menu_model.profile = host._profile
	menu_model.career = host._career
	host._menu.setup(menu_model, host._camera, ctrls)
	host._menu.chosen.connect(on_menu_event)
	Session.current = host._current_config()
	if show_main:
		open_menu_main()


func open_menu_main() -> void:
	host._menu.open_main()
	host.hud.hud.visible = false


func toggle_pause() -> void:
	if host._menu == null:
		return
	if host._menu.is_open():
		if host._menu.model.screen() == "pause":
			close_menu()
		return
	var in_game = host._mode.human_pitcher and host.lineup_mode == "Game" and host._game != null and not host._game.over and host.acts.scenario == null
	host._menu.model.can_mound_visit = in_game and not host.manager.visit_used
	host._menu.model.can_leave = in_game
	host._menu.open_pause(Session.current if Session.current != null else host._config)
	host._sfx("ui_pause_open")
	host.hud.hud.visible = false


func close_menu() -> void:
	host._sfx("ui_pause_close")
	host._menu.close()
	host.hud.hud.visible = true


func poll_menu_button() -> void:
	if not host._xr_active or host._off_hand == null or not host._off_hand.get_is_active():
		return
	var down = host._off_hand.is_button_pressed("menu_button")
	if down and not menu_button_was:
		toggle_pause()
	menu_button_was = down


func on_menu_event(ev: Dictionary) -> void:
	host.slog.record("menu", {"event": ev.get("type", ""), "config": (ev.config as GameConfig).to_dict() if ev.has("config") else {}})
	match String(ev.get("type", "")):
		"career_changed":
			host._career = host._menu.model.career
			if host._career != null:
				host._career.save()
			else:
				Career.delete_saved()
		"settings":
			host._settings.save()
			host.apply_assist(host._settings)
			host._haptics.set_level(host._settings.haptics)
			PitchLocation.colorblind = host._settings.colorblind
			if host._audio:
				host._audio.apply_volumes(host._settings.volumes)
		"start":
			Session.pending = ev.config
			host._settings.save()
			host.get_tree().reload_current_scene.call_deferred()
		"restart":
			Session.pending = Session.current if Session.current != null else host._config
			host.get_tree().reload_current_scene.call_deferred()
		"main_menu":
			Session.show_menu = true
			host.get_tree().reload_current_scene.call_deferred()
		"resume":
			close_menu()
		"intentional_walk":
			close_menu()
			host.manager.issue_intentional_walk()
		"mound_visit":
			close_menu()
			host.manager.mound_visit()
		"leave_game":
			close_menu()
			host.manager.leave_game()
		"quit":
			host.get_tree().quit()
