# Démo du module process : capture, pipes, délai, environnement.
use process

# 1. Capture simple (aucun shell : les arguments sont passés tels quels).
r := process.run("echo", ["bonjour", "$HOME"])
print(f"code={r.code} stdout={r.stdout}")

# 2. Construction fluide : dossier, environnement, stderr fusionné.
r = process.Command("sh", ["-c", "echo $GREETING depuis $(pwd); echo oups >&2"]).cwd("/tmp").env({"GREETING": "salut"}).stderr("stdout").run()
print(r.stdout)

# 3. Dialogue avec un fils : sort lit stdin, on lit sa sortie.
p := process.Command("sort").stdin("pipe").stdout("pipe").spawn()
p.write("pomme\nbanane\ncerise\n")
p.close_stdin()
print(p.read_all())
p.wait()
p.close()

# 4. Délai : TERM puis, si ignoré, KILL.
r = process.run("sleep", ["10"], null, 0.2)
print(f"timed_out={r.timed_out} code={r.code}")

# 5. Erreurs : un code non nul n'est une erreur qu'avec check.
try:
    process.check_output("sh", ["-c", "echo raté >&2; exit 4"])
catch e:
    print(e.type, "->", e.message)
