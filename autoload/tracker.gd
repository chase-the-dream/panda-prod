# tracker.gd - autoload singleton ("Tracker"). Reports which app the user is focused on.
# Spawns the tracker.py sidecar, which polls the Windows foreground window and sends
# JSON datagrams ({"app", "title", "pid", "ts"}) to 127.0.0.1:PORT over UDP.
extends Node

signal active_app_changed(app: String, title: String)

const PORT := 47823
const SPAWN_SIDECAR := true  # false: run `python sidecar/tracker.py` by hand instead
const PYTHON_CANDIDATES := ["python", "py"]

var current_app := ""
var current_title := ""

var _udp := PacketPeerUDP.new()
var _sidecar_pid := -1


func _ready() -> void:
	var err := _udp.bind(PORT, "127.0.0.1")
	if err != OK:
		push_error("Tracker: could not bind UDP port %d (error %d)" % [PORT, err])
		return
	if SPAWN_SIDECAR:
		_spawn_sidecar()


func _sidecar_script_path() -> String:
	if OS.has_feature("editor"):  # F5 / editor runs: use the project folder
		return ProjectSettings.globalize_path("res://sidecar/tracker.py")
	return OS.get_executable_path().get_base_dir().path_join("tracker.py")  # exported: beside the exe


func _spawn_sidecar() -> void:
	var script := _sidecar_script_path()
	if not FileAccess.file_exists(script):
		push_error("Tracker: tracker.py not found at %s" % script)
		return
	var args := [script, "--port", str(PORT), "--parent-pid", str(OS.get_process_id())]
	for exe in PYTHON_CANDIDATES:
		# Open a console in debug builds so the Python output is visible next to the pet.
		_sidecar_pid = OS.create_process(exe, args, OS.is_debug_build())
		if _sidecar_pid != -1:
			return
	push_error("Tracker: could not start tracker.py — is Python on PATH?")


func _process(_delta: float) -> void:
	while _udp.get_available_packet_count() > 0:
		var data = JSON.parse_string(_udp.get_packet().get_string_from_utf8())
		if not data is Dictionary:
			continue
		var app := str(data.get("app", ""))
		var title := str(data.get("title", ""))
		if app == current_app and title == current_title:
			continue
		current_app = app
		current_title = title
		print("[Tracker] %s | %s" % [app, title])
		active_app_changed.emit(app, title)


func _exit_tree() -> void:
	# tracker.py also exits on its own when this process dies (parent-pid watchdog).
	if _sidecar_pid > 0 and OS.is_process_running(_sidecar_pid):
		OS.kill(_sidecar_pid)
	_udp.close()
