# ALEX pure standard-library integration test
use core
use math
use string
use collections
use io
use os

func check(value, name):
    if not value:
        raise("AssertionError", name)

check(core.is_int(42), "core.is_int")
check(core.to_int(12.8) == 12, "core.to_int")
check(math.factorial(5) == 120, "math.factorial")
check(math.gcd(48, 18) == 6, "math.gcd")
check(string.upper("alex") == "ALEX", "string.upper")

values := [3, 1, 2]
collections.sort(values)
check(values[0] == 1, "collections.sort[0]")
check(values[1] == 2, "collections.sort[1]")
check(values[2] == 3, "collections.sort[2]")

path := "alex_pure_stdlib_test.tmp"
io.write_file(path, "ALEX")
check(io.file_exists(path), "io.file_exists")
check(io.read_file(path) == "ALEX", "io.read_file")
io.delete_file(path)
check(not io.file_exists(path), "io.delete_file")

check(os.is_dir(os.cwd()), "os.is_dir")
print("PURE STDLIB: OK")
