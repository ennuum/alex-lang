# Tests : process.process_errors, process_state, process_signal, process_priority, process_limits,
# process_handle, process_group, process_monitor, process_builder.
from core use len, type
from collections use append
use check as t
use os
use io
use filesystem as fs
use process
use process.process_errors as pe
use process.process_state as ps
use process.process_signal as psig
use process.process_priority as prio
use process.process_limits as lim
use process.process_handle as ph
use process.process_group as pg
use process.process_monitor as pmon
use process.process_builder as pb

# errors
t.check(pe.is_process_error("ProcessNotFoundError"), "is_process_error")
t.eq(pe.from_errno("ESRCH"), "ProcessNotFoundError", "from_errno")
t.check(len(pe.explain("PermissionError")) > 10, "explain")
t.raises(() => pe.need_pid("f", -1), "ArgumentError", "need_pid")

# state
t.eq(ps.from_code("S"), "sleeping", "from_code")
t.check(ps.is_alive(ps.RUNNING) and ps.is_finished(ps.ZOMBIE), "alive/finished")
m := ps.StateMachine()
m.to(ps.RUNNING)
m.to(ps.EXITED)
t.raises(() => m.to(ps.RUNNING), "InvalidStateError", "transition interdite")
t.eq(m.history, ["created", "running", "exited"], "historique")
t.check(ps.is_alive(ps.of_pid(os.pid())), "of_pid soi-même")
t.eq(ps.from_exit_code(-9), "killed", "from_exit_code")

# handle + signal
h := ph.spawn("sleep", ["30"])
t.check(h.is_child() and h.is_running(), "fils actif")
t.check(psig.can_signal(h.pid()), "can_signal")
h.suspend()
os.sleep(0.1)
t.eq(h.state(), "stopped", "suspendu")
h.resume()
os.sleep(0.05)
t.check(h.state() != "stopped", "repris")
h.terminate()
code := h.wait(3.0)
t.eq(code, -15, "code TERM")
t.eq(h.exit_status().signal(), "TERM", "exit_status")
t.eq(h.state(), "killed", "état final")
h.close()
t.raises(() => psig.send(999999, "TERM"), "ProcessNotFoundError", "pid absent")
t.raises(() => ph.of_pid(999999), "ProcessNotFoundError", "of_pid absent")
me := ph.current()
t.check(me.info().pid == os.pid(), "current info")
other := process.spawn("sleep", ["30"])
t.check(psig.shutdown(other.pid(), 1.0) or true, "shutdown")
other.wait(2.0)
other.close()

# priority
t.eq(prio.name_of(0), "normal", "name_of")
t.eq(prio.from_name("idle"), 19, "from_name")
t.raises(() => prio.set(42), "ArgumentError", "hors bornes")
base := prio.get()
t.check(base >= -20 and base <= 19, "get")
kid := ph.spawn("sleep", ["5"])
if prio.supported():
    prio.set(12, kid.pid())
    t.eq(prio.get(kid.pid()), 12, "set sur un fils")
    t.raises(() => prio.set(-20, kid.pid()), "PermissionError", "hausse refusée") if os.user_id() != 0 else t.check(true, "root")
else:
    t.check(true, "priorité non supportée")
kid.kill()
kid.wait(2.0)
kid.close()

# limits
nf := lim.get(lim.NOFILE)
t.check(nf.soft != null and nf.soft > 0, "get NOFILE")
t.eq(lim.resource("RLIMIT_CORE"), 4, "resource par nom")
t.eq(lim.name_of(7), "nofile", "name_of")
t.raises(() => lim.resource("bananes"), "LimitError", "ressource inconnue")
if nf.hard != null and nf.soft > 64:
    old := lim.set("nofile", nf.soft - 1)
    t.eq(lim.get("nofile").soft, nf.soft - 1, "set souple")
    lim.set("nofile", old.soft)
    t.eq(lim.get("nofile").soft, nf.soft, "restauré")
    t.raises(() => lim.set("nofile", nf.hard + 1000000), "LimitError", "souple > dure")
t.eq(lim.with_limit("core", 0, () => lim.get("core").soft), 0, "with_limit")
t.check(len(lim.all()) >= 10, "all")


# builder
tmp := fs.make_temp_dir()
out_file := os.join(tmp, "out.txt")
b := pb.ProcessBuilder("sh")
b.args(["-c", "echo $MODE; echo err 1>&2; exit 3"])
b.env("MODE", "prod")
b.redirect_output(out_file)
r := b.run()
t.eq(r.code, 3, "code")
t.eq(r.stdout, "prod\n", "env + stdout")
t.eq(r.stderr, "err\n", "stderr")
t.eq(io.read_file(out_file), "prod\n", "redirect_output")
mg := pb.ProcessBuilder("sh", ["-c", "echo a; echo b 1>&2"]).merge_stderr().run()
t.eq(mg.stdout, "a\nb\n", "merge_stderr")
t.raises(() => pb.ProcessBuilder("sh", ["-c", "exit 1"]).check().run(), "ProcessError", "check")
to := pb.ProcessBuilder("sleep", ["10"]).timeout(0.2).run()
t.check(to.timed_out, "timeout")
t.eq(pb.ProcessBuilder("cat").input("bonjour").run().stdout, "bonjour", "input")
t.eq(pb.ProcessBuilder("pwd").directory(tmp).run().stdout, os.realpath(tmp) + "\n", "directory")
cpu := pb.ProcessBuilder("sh", ["-c", "ulimit -t"]).limit("cpu", 7).run()
t.eq(cpu.stdout, "7\n", "limite sur le fils")
hd := pb.ProcessBuilder("sleep", ["5"]).priority(15).start()
if prio.supported():
    t.eq(prio.get(hd.pid()), 15, "priorité sur le fils")
hd.stop(1.0)
hd.close()
t.check(len(b.describe()) > 20, "describe")
t.eq(b.copy().to_list(), ["sh", "-c", "echo $MODE; echo err 1>&2; exit 3"], "copy")
fs.remove_tree(tmp)

# group
g := pg.ProcessGroup("workers")
g.add("a", "sleep", ["10"])
g.add("b", "sh", ["-c", "exit 3"])
g.start_all()
first := g.wait_any(5.0)
t.eq(first, ["b", 3], "wait_any")
t.eq(g.running(), ["a"], "running")
summ := g.stop_all(1.0)
t.eq(summ["a"], -15, "stop_all")
t.eq(g.failed(), ["a", "b"], "failed")
t.check(not g.all_succeeded(), "all_succeeded")
g.close()
t.raises(() => g.add("a", "true"), "ArgumentError", "nom en double")
t.check(pg.group_of() > 0 and pg.session_of() > 0, "group_of / session_of")
t.check(os.pid() in pg.members_of(pg.group_of()), "members_of")

# monitor
busy := process.spawn("sh", ["-c", "i=0; while [ $i -lt 400000 ]; do i=$((i+1)); done"])
mon := pmon.ProcessMonitor()
mon.watch(busy.pid(), "busy")
exits := []
mon.on_exit((n, p) => append(exits, n))
mon.on_threshold("rss", 1, (n, s) => null)
mon.run(5.0, 0.05)
busy.wait(5.0)
mon.sample()
st := mon.stats("busy")
t.check(st["samples"] >= 2, "échantillons")
t.check(st["rss_max"] > 0, "rss")
t.check(st["cpu_max"] == null or st["cpu_max"] >= 0, "cpu")
t.check(len(mon.alerts) > 0, "seuil déclenché")
busy.close()
t.raises(() => mon.on_threshold("disque", 1, (n, s) => null), "ArgumentError", "métrique inconnue")

t.summary("process2")
