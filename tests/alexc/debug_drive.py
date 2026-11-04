import json, subprocess, sys, os, threading, queue
exe, mode = sys.argv[1], sys.argv[2]
PROG = os.path.abspath("tests/tooling/dbg/prog.al")
def L(t):
    for i,l in enumerate(open(PROG),1):
        if t in l: return i
if mode == "2":
    p = subprocess.Popen([exe,"debug","--protocol","2","--break-on-exception",PROG], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
else:
    p = subprocess.Popen([exe,"debug",PROG], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
q = queue.Queue()
def rd():
    for line in p.stdout: q.put(line.decode())
    q.put(None)
threading.Thread(target=rd, daemon=True).start()
out=[]
def wait(kind):
    while True:
        l = q.get(timeout=20)
        if l is None: return None
        out.append(l)
        if json.loads(l).get("event") == kind: return l
def send(**c): p.stdin.write((json.dumps(c)+"\n").encode()); p.stdin.flush()
if mode == "2":
    wait("paused")
    send(command="breakpoints.set", file=PROG, breakpoints=[{"line":L("self.solde = self.solde + montant"),"condition":"montant > 10"},{"line":L("somme = somme + v"),"logMessage":"s={somme} v={v} {inconnu} {[1,2]}"}], id=1); wait("ack")
    send(command="continue"); wait("ack"); wait("paused")
    for e in ["self", "self.historique", "len(self.historique) * 2.5", "montant // 3", "-montant % 7", "\"a\" + self.nom", "self.nom[0]", "type(self)", "str(self.historique)", "1 +", "notes", "10 / 4", "2 ** 10", "x.y(", "self.inconnu", "montant.x", "c"]:
        send(command="evaluate", expression=e, id=e); wait("evaluate")
    send(command="evaluate", expression="notes", frame=1); wait("evaluate")
    for r in range(1,8):
        send(command="variables", ref=r); wait("variables") if True else None
    send(command="step", mode="into"); wait("ack"); wait("paused")
    send(command="step", mode="over"); wait("ack"); wait("paused")
    send(command="breakpoints.set", file=PROG, breakpoints=[]); wait("ack")
    send(command="frob", id=9); wait("error")
    send(command="continue"); wait("ack")
    wait("input"); send(command="input", text="Zoé"); wait("ack")
    wait("paused"); send(command="exceptions", **{"break": False}); wait("ack"); send(command="continue"); wait("ack")
    wait("exception")
else:
    wait("paused")
    send(command="breakpoint.add", file=PROG, line=L("somme = somme + v")); wait("breakpoint")
    send(command="bogus"); wait("error")
    send(command="continue"); wait("paused")
    send(command="step", mode="over"); wait("paused")
    send(command="breakpoint.remove", file=PROG, line=L("somme = somme + v")); wait("breakpoint")
    send(command="continue")
    wait("terminated") if False else None
p.stdin.close()
while True:
    l = q.get(timeout=20)
    if l is None: break
    out.append(l)
p.wait()
sys.stdout.write("".join(out)); print("rc", p.returncode)
print("STDERR", p.stderr.read().decode())
