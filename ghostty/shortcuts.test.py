#!/usr/bin/env python3
"""Isolated terminal regression checks: python3 ghostty/shortcuts.test.py -v."""
import json
import os
from pathlib import Path
import pty
import select
import shlex
import shutil
import signal
import struct
import subprocess
import tempfile
import termios
import fcntl
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
TMUX = shutil.which("tmux") or "tmux"
NVIM = shutil.which("nvim") or "nvim"
# xterm Ctrl-Shift-F1..F9: deliberately not Super/kitty modifiers.
KEYS = dict(zip("pswf/hjkl", (b"\x1b[1;6P", b"\x1b[1;6Q", b"\x1b[1;6R",
    b"\x1b[1;6S", b"\x1b[15;6~", b"\x1b[17;6~", b"\x1b[18;6~",
    b"\x1b[19;6~", b"\x1b[20;6~")))


class Terminal:
    def __init__(self, argv, env, cwd):
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.chdir(cwd)
            os.execvpe(argv[0], argv, env)
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))

    def drain(self, seconds=0.05):
        output = b""
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if select.select([self.fd], [], [], 0.01)[0]:
                try:
                    chunk = os.read(self.fd, 65536)
                    output += chunk
                    # fzf waits for cursor and bracketed-paste mode reports.
                    for _ in range(chunk.count(b"\x1b[6n")):
                        os.write(self.fd, b"\x1b[1;1R")
                    if b"\x1b[?2004$p" in chunk:
                        os.write(self.fd, b"\x1b[?2004;1$y")
                except OSError:
                    break
        return output

    def send(self, data):
        os.write(self.fd, data)
        return self.drain(0.1)

    def close(self):
        try:
            os.kill(self.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        os.close(self.fd)
        os.waitpid(self.pid, 0)


class Shortcuts(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="shortcut-", dir="/tmp")
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name).resolve()
        self.env = dict(PATH=os.environ["PATH"], HOME=str(self.home), TERM="xterm-256color",
                        LANG="en_US.UTF-8", XDG_CONFIG_HOME=str(self.home / "config"),
                        XDG_DATA_HOME=str(self.home / "data"), XDG_STATE_HOME=str(self.home / "state"))
        self.socket = str(self.home / "tmux")
        self.rpc = str(self.home / "nvim")
        self.terminal: Terminal

    def tmux(self, *args):
        return subprocess.check_output([TMUX, "-S", self.socket, *args], env=self.env,
                                       cwd=self.home, text=True, stderr=subprocess.STDOUT, timeout=5).strip()

    def start(self, through_tmux=False, configured=False, after=None):
        init = self.home / "init.lua"
        init.write_text("vim.o.swapfile = false\nvim.o.shadafile = 'NONE'\n"
                        "vim.g.seen = {}\nvim.on_key(function(k) "
                        "local t = vim.g.seen; table.insert(t, vim.fn.keytrans(k)); vim.g.seen = t end)\n")
        argv = [NVIM, "-u", str(init), "-i", "NONE", "--listen", self.rpc]
        if through_tmux:
            command = shlex.join(argv)
            if after:
                command = shlex.join(["/bin/zsh", "-f", "-i", "-c", command + "; exec " + shlex.join(after)])
            self.tmux("-f", "/dev/null", "new-session", "-d", "-s", "test", "-x", "120", "-y", "40",
                      command)
            self.addCleanup(lambda: subprocess.run([TMUX, "-S", self.socket, "kill-server"],
                                                   env=self.env, capture_output=True))
            if configured:
                # Only TPM is excluded: loading it would start restore/background jobs.
                conf = (ROOT / "tmux/.tmux.conf").read_text().replace(
                    "run '~/.tmux/plugins/tpm/tpm'", "# TPM excluded in isolated test")
                (self.home / "tmux.conf").write_text(conf)
                self.tmux("source-file", str(self.home / "tmux.conf"))
            argv = [TMUX, "-S", self.socket, "attach-session", "-t", "test"]
        self.terminal = Terminal(argv, self.env, self.home)
        self.addCleanup(self.terminal.close)
        deadline = time.monotonic() + 5
        while not Path(self.rpc).exists() and time.monotonic() < deadline:
            self.terminal.drain()
        self.assertTrue(Path(self.rpc).exists(), "isolated Neovim did not start")
        self.terminal.drain(0.4)

    def lua(self, code):
        self.terminal.drain()
        expr = "json_encode(luaeval('" + code.replace("'", "''") + "'))"
        result = subprocess.check_output([NVIM, "--server", self.rpc, "--remote-expr", expr],
                                         env=self.env, text=True, timeout=5)
        return json.loads(result)

    def execute(self, code):
        return self.lua("(function() " + code + " end)()")

    def load_maps(self):
        for name in ("remap.lua", "winmove.lua"):
            self.lua("dofile(" + json.dumps(str(ROOT / "nvim/lua/whitelight" / name)) + ")")

    def ghostty_keys(self):
        bindings = {}
        for line in (ROOT / "ghostty/config").read_text().splitlines():
            if line.startswith("keybind = super+"):
                chord, action = line.removeprefix("keybind = super+").split("=", 1)
                bindings[chord] = action
        return bindings

    def send_chord(self, chord):
        action = self.ghostty_keys()[chord]
        self.assertTrue(action.startswith("csi:"), f"Cmd-{chord} still sends editor text: {action}")
        self.terminal.send(b"\x1b[" + action.removeprefix("csi:").encode())

    def check_transport(self, through_tmux):
        self.start(through_tmux)
        for sequence in KEYS.values():
            self.terminal.send(sequence)
        self.assertEqual(self.lua("vim.g.seen"), [f"<F{i}>" for i in range(37, 46)])

    def test_transport_direct(self):
        self.check_transport(False)

    def test_transport_tmux(self):
        self.check_transport(True)

    def test_config_has_no_editor_text(self):
        bindings = self.ghostty_keys()
        for chord, sequence in KEYS.items():
            with self.subTest(chord=chord):
                self.assertEqual(bindings[chord], "csi:" + sequence[2:].decode())

    def recorder(self):
        path = self.home / "input.bin"
        script = self.home / "record.py"
        script.write_text("import os, tty\nfrom pathlib import Path\n"
                          "tty.setraw(0)\nf = open('input.bin', 'wb', buffering=0)\n"
                          "Path('ready').touch()\nwhile True:\n f.write(os.read(0, 1024))\n")
        return [shutil.which("python3") or "python3", str(script)], path

    def wait_file(self, path):
        deadline = time.monotonic() + 5
        while not path.exists() and time.monotonic() < deadline:
            self.terminal.drain()
        self.assertTrue(path.exists(), f"fixture not ready: {path.name}")

    def test_non_editor_pane_switch(self):
        self.start(through_tmux=True, configured=True)
        self.load_maps()
        editor = self.tmux("display-message", "-p", "#{pane_id}")
        argv, path = self.recorder()
        other = self.tmux("split-window", "-h", "-P", "-F", "#{pane_id}", shlex.join(argv))
        self.wait_file(self.home / "ready")
        for chord in KEYS:
            self.send_chord(chord)
        self.assertEqual(path.read_bytes(), b"")
        self.terminal.send(b"a")
        self.assertEqual(path.read_bytes(), b"a", "recorder must receive ordinary keys")
        self.tmux("select-pane", "-t", editor)
        self.tmux("select-pane", "-t", other)
        for chord in KEYS:
            self.send_chord(chord)
        self.assertEqual(path.read_bytes(), b"a")

    def test_same_pane_after_editor_exit(self):
        argv, path = self.recorder()
        self.start(through_tmux=True, configured=True, after=argv)
        self.load_maps()
        pane = self.tmux("display-message", "-p", "#{pane_id}")
        self.assertEqual(self.tmux("display-message", "-p", "#{pane_current_command}"), "nvim")
        self.lua("vim.schedule(function() vim.cmd('qa!') end)")
        self.wait_file(self.home / "ready")
        self.assertEqual(self.tmux("display-message", "-p", "#{pane_id}"), pane)
        self.assertNotEqual(self.tmux("display-message", "-p", "#{pane_current_command}"), "nvim")
        for chord in KEYS:
            self.send_chord(chord)
        self.assertEqual(path.read_bytes(), b"")
        self.terminal.send(b"a")
        self.assertEqual(path.read_bytes(), b"a", "same-pane recorder must receive ordinary keys")

    def test_copy_mode(self):
        self.start(through_tmux=True, configured=True)
        self.load_maps()
        self.tmux("copy-mode")
        for chord in KEYS:
            self.send_chord(chord)
        self.assertEqual(self.lua("vim.g.seen"), [])
        self.assertEqual(self.tmux("display-message", "-p", "#{pane_in_mode}"), "1")

    def test_editor_commandline_and_operator(self):
        self.start(through_tmux=True, configured=True)
        self.load_maps()
        self.terminal.send(b":echo keep")
        for chord in KEYS:
            self.send_chord(chord)
        self.assertEqual(self.lua("vim.fn.getcmdline()"), "echo keep")
        self.assertEqual(self.lua("vim.api.nvim_get_mode().mode"), "c")
        self.terminal.send(b"\x1b")
        self.lua("vim.api.nvim_buf_set_lines(0, 0, -1, false, {'keep'})")
        self.terminal.send(b"d")
        for chord in KEYS:
            self.send_chord(chord)
        self.assertEqual(self.lua("vim.api.nvim_buf_get_lines(0, 0, -1, false)"), ["keep"])
        self.assertTrue(self.lua("vim.api.nvim_get_mode().mode").startswith("no"))

    def test_editor_terminal(self):
        self.start(through_tmux=True, configured=True)
        self.load_maps()
        argv, path = self.recorder()
        self.lua("vim.fn.termopen(" + "{" + ",".join(map(json.dumps, argv)) + "})")
        self.lua("vim.cmd('startinsert')")
        self.wait_file(self.home / "ready")
        for chord in KEYS:
            self.send_chord(chord)
        self.assertEqual(path.read_bytes(), b"")
        self.terminal.send(b"a")
        self.assertEqual(path.read_bytes(), b"a")

    def test_picker_dispatch(self):
        self.start(through_tmux=True, configured=True)
        self.load_maps()
        # The slow, user-data-dependent picker UI is the boundary, not the key mappings.
        self.lua("vim.api.nvim_create_user_command('Telescope', function(o) vim.g.picker = o.args end, {nargs='+'})")
        self.lua("vim.api.nvim_create_user_command('Wiki', function() vim.g.picker = 'wiki' end, {})")
        for mode in (b"", b"i"):
            self.terminal.send(mode)
            for chord, expected in (("p", "find_files"), ("f", "live_grep"), ("w", "wiki")):
                self.send_chord(chord)
                self.assertEqual(self.lua("vim.g.picker"), expected)
            self.terminal.send(b"\x1b")

    def test_comments(self):
        self.start(through_tmux=True, configured=True)
        self.load_maps()
        self.execute("vim.bo.commentstring = '# %s'")
        self.lua("vim.api.nvim_buf_set_lines(0, 0, -1, false, {'one', 'two'})")
        self.send_chord("/")
        self.assertEqual(self.lua("vim.api.nvim_buf_get_lines(0, 0, -1, false)"), ["# one", "two"])
        self.terminal.send(b"i")
        self.send_chord("/")
        self.assertEqual(self.lua("vim.api.nvim_buf_get_lines(0, 0, -1, false)"), ["one", "two"])
        self.assertEqual(self.lua("vim.api.nvim_get_mode().mode"), "i")
        self.terminal.send(b"\x1bggVj")
        self.send_chord("/")
        self.assertEqual(self.lua("vim.api.nvim_buf_get_lines(0, 0, -1, false)"), ["# one", "# two"])

    def test_windows(self):
        self.start(through_tmux=True, configured=True)
        self.load_maps()
        for mode in (b"", b"i"):
            for chord, opposite in (("h", "l"), ("j", "k"), ("k", "j"), ("l", "h")):
                self.lua("vim.cmd('only!')")
                self.terminal.send(mode)
                self.send_chord(chord)
                self.assertEqual(len(self.lua("vim.api.nvim_list_wins()")), 2)
                edge = self.lua("vim.api.nvim_get_current_win()")
                self.assertEqual(self.lua(f"vim.fn.winnr('{chord}')"), self.lua("vim.fn.winnr()"))
                self.send_chord(opposite)
                self.assertNotEqual(self.lua("vim.api.nvim_get_current_win()"), edge)
                self.assertEqual(len(self.lua("vim.api.nvim_list_wins()")), 2)
                self.terminal.send(b"\x1b")

    def test_save_guards(self):
        self.start(through_tmux=True, configured=True)
        self.load_maps()
        target = self.home / "readonly.txt"
        target.write_text("original\n")
        self.lua("vim.cmd.edit(" + json.dumps(str(target)) + ")")
        self.lua("vim.api.nvim_buf_set_lines(0, 0, -1, false, {'changed'})")
        self.execute("vim.bo.readonly = true")
        self.send_chord("s")
        self.assertEqual(target.read_text(), "original\n")
        self.assertTrue(self.lua("vim.bo.modified"))
        self.assertIn("E45", self.lua("vim.v.errmsg"))
        self.terminal.send(b"\x1b")
        self.execute("vim.bo.readonly = false; vim.bo.buftype = 'nofile'; vim.v.errmsg = ''")
        self.send_chord("s")
        self.assertEqual(target.read_text(), "original\n")
        self.assertIn("E382", self.lua("vim.v.errmsg"))

    def start_shell(self):
        # Load the actual fzf/binding section, without startup hooks or personal configuration.
        rc = (ROOT / "zsh/.zshrc").read_text()
        section = rc[rc.index("source <(fzf --zsh)"):rc.index("# fd honours")]
        script = self.home / "shell.zsh"
        script.write_text(section + "\nPROMPT='test> '\n"
            "snapshot() { print -r -- \"$PWD\" > cwd; print -rn -- \"$BUFFER\" > buffer; }\n"
            "zle -N snapshot\n"
            "for map in emacs viins vicmd; do\n"
            "  bindkey -M $map '^G' snapshot\n"
            "  bindkey -M $map '^Xc' >> bindings\n"
            "done\n"
            "bindkey -e\nprint ready > ready\n")
        self.terminal = Terminal(["/bin/zsh", "-f"], self.env, self.home)
        self.addCleanup(self.terminal.close)
        self.terminal.drain(0.2)
        self.terminal.send(("source " + shlex.quote(str(script)) + "\n").encode())
        self.wait_file(self.home / "ready")
        self.terminal.drain(0.2)

    def test_direct_shell_swallows_editor_keys(self):
        self.start_shell()
        self.terminal.send(b"keep")
        for chord in KEYS:
            self.send_chord(chord)
        self.terminal.send(b"\x07")
        self.assertEqual((self.home / "buffer").read_bytes(), b"keep")
        self.assertEqual((self.home / "cwd").read_text().strip(), str(self.home))

    def test_directory_picker_selection_and_cancel(self):
        chosen = self.home / "chosen folder"
        chosen.mkdir()
        self.env["FZF_ALT_C_COMMAND"] = "printf '%s\\n' 'chosen folder'"
        self.env["FZF_DEFAULT_OPTS"] = "--no-height"
        self.start_shell()
        self.assertEqual((self.home / "bindings").read_text().count("fzf-cd-widget"), 3,
                         "directory picker must be reachable in emacs/vi keymaps")
        self.terminal.send(b"keep\x18c")
        self.terminal.drain(0.3)
        self.terminal.send(b"\x1b")
        self.terminal.drain(0.3)
        self.terminal.send(b"\x07")
        self.assertEqual((self.home / "buffer").read_bytes(), b"keep")
        self.assertEqual((self.home / "cwd").read_text().strip(), str(self.home))
        self.terminal.send(b"\x18c")
        self.terminal.drain(0.3)
        self.terminal.send(b"\r")
        self.terminal.drain(0.3)
        self.terminal.send(b"\x07")
        self.assertTrue((chosen / "cwd").exists(), "Ctrl-X c did not open the directory picker")
        self.assertEqual((chosen / "cwd").read_text().strip(), str(chosen))
        self.assertEqual((chosen / "buffer").read_bytes(), b"keep")

    def test_plugin_save_picker_and_restore_bindings(self):
        self.start(through_tmux=True, configured=True)
        env = dict(self.env, TMUX=f"{self.socket},{self.tmux('display-message', '-p', '#{pid}')},0")
        # Initializers bind keys only; neither save nor restore is invoked.
        plugins = Path.home() / ".tmux/plugins"
        self.tmux("set-option", "-g", "@fuzzmux-jumplist-enabled", "0")
        for plugin in ("tmux-resurrect/resurrect.tmux", "fuzzmux.tmux/fuzzmux.tmux"):
            subprocess.run(["/opt/homebrew/bin/bash", str(plugins / plugin)], env=env,
                           cwd=self.home, capture_output=True, check=True, timeout=10)
        bindings = self.tmux("list-keys", "-T", "prefix")
        for key, script in (("C-x", "scripts/save.sh"), ("C-s", "fzf_pane_switcher.sh"),
                            ("C-r", "scripts/restore.sh")):
            with self.subTest(key=key):
                binding = next((line for line in bindings.splitlines()
                                if line.split()[3] == key), "")
                self.assertIn(script, binding)
        self.assertEqual(self.tmux("show-option", "-gv", "@continuum-save-interval"), "15")
        self.assertEqual(self.tmux("show-option", "-gv", "@continuum-restore"), "on")

    def test_clipboard_delete_is_not_shadowed(self):
        self.start()
        self.load_maps()
        for mode in ("n", "x"):
            self.assertEqual(self.lua(f"vim.fn.maparg(' d', '{mode}')"), '\"+d<CR>')
        self.assertEqual(self.lua("vim.fn.maparg('<C-d>', 'n')"), "<C-D>zz")

    def test_save(self):
        self.start(through_tmux=True, configured=True)
        self.load_maps()
        target = self.home / "saved.txt"
        self.lua("vim.cmd.edit(" + json.dumps(str(target)) + ")")
        self.terminal.send(b"ihello")
        self.send_chord("s")
        self.assertTrue(target.exists(), "Cmd-S did not write the file")
        self.assertEqual(target.read_text(), "hello\n")
        self.assertEqual(self.lua("vim.api.nvim_get_mode().mode"), "i")
        self.terminal.send(b"\x1b")
        self.lua("vim.api.nvim_buf_set_lines(0, 0, -1, false, {'normal'})")
        self.send_chord("s")
        self.assertEqual(target.read_text(), "normal\n")


if __name__ == "__main__":
    unittest.main()
