# Modules io et os natifs (appels système Linux) : fichiers, environnement, processus, exit.
use io
use os
p := "/tmp/alex_native_io_test.txt"
io.write_file(p, "ligne 1\nété\n")
io.append_file(p, "fin")
print(io.read_file(p))
print(io.file_exists(p), io.file_exists("/tmp/claude-0/sp"), io.file_exists("/nope"))
io.delete_file(p)
print(io.file_exists(p))
print(os.name(), os.platform(), os.arch())
print(os.args(), os.argc())
print(os.getenv("ALEX_TEST_VAR"), os.getenv("NOPE_X"), os.getenv("NOPE_X", "def"), os.hasenv("ALEX_TEST_VAR"))
print(os.pid() > 0, os.parent_pid() > 0)
print(os.exists("/tmp"), os.isdir("/tmp"), os.isfile("/tmp"), os.isfile("/etc/hostname"))
os.chdir("/tmp")
print(os.cwd())
print(os.hostname() != "", os.version() != "")
try:
    io.read_file("/nope/x")
catch e:
    print(e)
try:
    os.chdir("/nonexistent")
catch e:
    print(e)
d := "/tmp/alex_native_dir_test"
if os.isdir(d):
    os.rmdir(d)
os.mkdir(d)
print(os.isdir(d), os.isfile(d))
io.write_file(d + "/f.txt", "x")
for bad in [() => os.mkdir(d), () => os.rmdir(d), () => os.remove(d), () => os.rmdir(d + "/f.txt"), () => os.mkdir("/nope/a/b"), () => os.remove(d + "/absent")]:
    try:
        bad()
    catch e:
        print(e)
os.remove(d + "/f.txt")
os.rmdir(d)
print(os.exists(d))
os.exit(4)
print("jamais")
