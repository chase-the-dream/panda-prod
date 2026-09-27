# tracker.gd - autoload singleton ("Tracker"). Reports which app the user is focused on.
# Spawns the tracker.py sidecar, which polls the Windows foreground window and sends
# JSON datagrams ({"app", "title", "pid", "ts"}) to 127.0.0.1:PORT over UDP.
# The port doubles as the single-instance lock: if it's taken, PandaProd is already running.
extends Node

signal active_app_changed(app: String, title: String)

const PORT := 47823
const SPAWN_SIDECAR := true  # false: run `python sidecar/tracker.py` by hand instead
# [exe, args...]. The py launcher first: it only exists with a real Python install, while
# "python" may be the Microsoft Store placeholder, which starts fine and then exits at once.
const PYTHON_CANDIDATES := [["py", "-3"], ["python"]]
const SPAWN_CHECK_TIME := 2.0  # s a started sidecar must stay up to count as running

var current_app := ""
var current_title := ""
var another_instance := false  # this copy found PandaProd already running and is quitting

var _udp := PacketPeerUDP.new()
var _sidecar_pid := -1


func _ready() -> void:
	var err := _udp.bind(PORT, "127.0.0.1")
	if err != OK:
		another_instance = true
		OS.alert("PandaProd is already running.\n\n(If it isn't, another program is using port %d.)"
				% PORT, "PandaProd")
		get_tree().quit()
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
		_sidecar_failed("tracker.py not found at %s" % script)
		return
	var args := [script, "--port", str(PORT), "--parent-pid", str(OS.get_process_id())]
	for candidate: Array in PYTHON_CANDIDATES:
		# Open a console in debug builds so the Python output is visible next to the pet.
		var pid := OS.create_process(candidate[0], candidate.slice(1) + args, OS.is_debug_build())
		if pid == -1:
			continue
		await get_tree().create_timer(SPAWN_CHECK_TIME).timeout
		if OS.is_process_running(pid):
			_sidecar_pid = pid
			return
	_sidecar_failed("could not start tracker.py with Python 3")


# Without the sidecar the mood only ever drifts down, so say so rather than fail silently.
func _sidecar_failed(reason: String) -> void:
	push_error("Tracker: %s" % reason)
	OS.alert("PandaProd couldn't start its app tracker (%s), so your panda can't see what you're "
			% reason + "working on.\n\nInstall Python 3 from python.org, then restart PandaProd.",
			"PandaProd")


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
		# Window titles are private (mail subjects, documents, tabs): never in release output.
		if OS.is_debug_build():
			print("[Tracker] %s | %s" % [app, title])
		active_app_changed.emit(app, title)


func _exit_tree() -> void:
	# tracker.py also exits on its own when this process dies (parent-pid watchdog).
	if _sidecar_pid > 0 and OS.is_process_running(_sidecar_pid):
		OS.kill(_sidecar_pid)
	_udp.close()
