# Tests : filesystem.path, file, directory, metadata, permissions, watch_service, filesystem_mount, errors.
from core use len, type
from collections use append
use check as t
use os
use io
use filesystem as fs
use filesystem.path as fp
use filesystem.file as ff
use filesystem.directory as dirs
use filesystem.metadata as md
use filesystem.permissions as perm
use filesystem.watch_service as ws
use filesystem.filesystem_mount as fm
use filesystem.filesystem_errors as fe

tmp := fs.make_temp_dir()

# errors
t.raises(() => fe.need_file("f", os.join(tmp, "nope")), "FileNotFoundError", "need_file absent")
t.raises(() => fe.need_file("f", tmp), "IsADirectoryError", "need_file dossier")
t.raises(() => fe.need_dir("f", "/etc/hostname"), "NotADirectoryError", "need_dir")
try:
    io.read_file(os.join(tmp, "nope"))
catch e:
    t.eq(fe.classify(e), "FileNotFoundError", "classify ENOENT")

# path
p := fp.Path(tmp) / "data" / "ventes.csv"
t.eq(p.name, "ventes.csv", "name")
t.eq(p.stem, "ventes", "stem")
t.eq(p.suffix, ".csv", "suffix")
t.check(p.parent() == fp.Path(tmp) / "data", "parent")
p.parent().mkdir()
p.write_text("a;b\n")
t.eq(p.read_text(), "a;b\n", "write/read")
t.check(p.is_file() and p.exists(), "is_file")
t.eq(str(p.with_suffix(".bak").name), "ventes.bak", "with_suffix")
t.eq(str(p.relative_to(tmp)), "data/ventes.csv", "relative_to")
t.check(p.is_relative_to(tmp), "is_relative_to")
t.eq(len(fp.Path(tmp).glob("**/*.csv")), 1, "glob")
q := p.copy_to(os.join(tmp, "copie.csv"))
t.check(q.exists(), "copy_to")
t.check(fp.home().is_dir(), "home")
t.eq(p.size(), 4, "size")
t.check(fp.Path("a/b") == "a/./b", "égalité normalisée")

# file
src := os.join(tmp, "a.txt")
io.write_file(src, "bonjour")
dst := os.join(tmp, "b.txt")
t.check(ff.copy(src, dst), "copy")
t.check(ff.same_content(src, dst), "same_content")
t.check(not ff.copy(src, dst, "never"), "never")
t.raises(() => ff.copy(src, dst, "error"), "FileExistsError", "error")
t.eq(ff.checksum(src), ff.checksum(dst), "checksum")
t.eq(len(ff.checksum(src)), 64, "sha256 hex")
ff.backup(src, 2)
io.write_file(src, "v2")
ff.backup(src, 2)
t.eq(io.read_file(src + ".1"), "v2", "backup rotation 1")
t.eq(io.read_file(src + ".2"), "bonjour", "backup rotation 2")
t.eq(len(ff.backups(src)), 2, "backups")
ff.replace(src, "v3")
t.eq(io.read_file(src + ".bak"), "v2", "replace .bak")
t.eq(io.read_file(src), "v3", "replace")
big := os.join(tmp, "big.bin")
io.write_bytes(big, [i % 256 for i in 0..1000])
parts := ff.split(big, 300)
t.eq(len(parts), 4, "split")
ff.join(parts, os.join(tmp, "big2.bin"))
t.check(ff.same_content(big, os.join(tmp, "big2.bin")), "join")
io.write_file(os.join(tmp, "c.txt"), "bonjour")
t.eq(len(ff.duplicates([dst, os.join(tmp, "c.txt"), src])), 1, "duplicates")
t.eq(ff.extension_of("x/y.tar.gz"), ".gz", "extension_of")

# metadata
m := md.of(dst)
t.eq(m.kind, "file", "kind")
t.eq(m.size, 7, "size")
t.check(m.owner() != null, "owner")
t.check(m.age() >= 0, "age")
t.eq(md.of(tmp).kind, "dir", "dossier")
t.check(md.same_file(dst, dst) and not md.same_file(dst, src), "same_file")
t.eq(md.format_size(1536), "1.5 Kio", "format_size")
t.raises(() => md.of(os.join(tmp, "nope")), "FileNotFoundError", "absent")

# permissions
os.chmod(dst, perm.parse("0644"))
pp := perm.of(dst)
t.eq(pp.octal(), "0644", "octal")
t.eq(pp.symbolic(), "rw-r--r--", "symbolic")
t.eq(perm.chmod(dst, "u+x"), perm.parse("0744"), "u+x")
t.eq(perm.chmod(dst, "go="), perm.parse("0700"), "go=")
t.eq(perm.chmod(dst, "a+r,u-x"), perm.parse("0644"), "clauses multiples")
t.eq(perm.apply(perm.parse("0644"), "a+x"), perm.parse("0755"), "apply")
t.eq(perm.apply(0, "0750"), perm.parse("0750"), "apply octal")
perm.make_private(dst)
t.check(perm.is_private(dst), "is_private")
t.check(perm.can_read(dst) and perm.can_write(dst), "can_read/write")
t.raises(() => perm.apply(0, "z+r"), "ArgumentError", "expression invalide")

# directory
d := dirs.Directory(os.join(tmp, "proj"))
d.create()
io.write_file(d.file_path("main.al"), "x")
d.child("lib").create()
io.write_file(os.join(os.join(d.path, "lib"), "u.al"), "yy")
t.eq(d.files(), ["main.al"], "files")
t.eq(d.subdirs(), ["lib"], "subdirs")
t.eq(len(d.find("*.al")), 2, "find")
t.eq(d.size(), 3, "size")
t.eq(d.largest(1)[0][1], 2, "largest")
mir := os.join(tmp, "miroir")
r := d.sync_to(mir)
t.eq(len(r["copied"]), 2, "sync copie")
r2 := d.sync_to(mir)
t.eq(r2["skipped"], 2, "sync rien de neuf")
io.write_file(os.join(mir, "extra.txt"), "z")
r3 := d.sync_to(mir, true)
t.eq(r3["deleted"], ["extra.txt"], "delete_extra")
t.check(dirs.identical(d.path, mir), "identical")
io.write_file(os.join(mir, "main.al"), "changé")
c := dirs.compare(d.path, mir)
t.eq(c["different"], ["main.al"], "compare")
t.raises(() => d.remove(), "DirectoryNotEmptyError", "remove non vide")
d.child("vide").create().remove()
d.remove(true)
t.check(not d.exists(), "remove récursif")

# watch_service
wd := os.join(tmp, "watch")
os.mkdir(wd)
s := ws.WatchService()
k := s.register(wd, null, ["*.toml"])
io.write_file(os.join(wd, "app.toml"), "a=1")
io.write_file(os.join(wd, "notes.txt"), "x")
keys := s.poll(1.0)
evs := []
for kk in keys:
    for e in kk.events():
        append(evs, e)
t.check(len(evs) >= 1, "événements reçus")
ok := true
for e in evs:
    if e.name != "app.toml":
        ok = false
t.check(ok, "filtre glob")
got := []
s.on((e) => append(got, e.kind))
io.write_file(os.join(wd, "app.toml"), "a=2")
os.sleep(0.05)
s.dispatch(1.0)
t.check(len(got) >= 1, "dispatch")
t.raises(() => s.register(os.join(tmp, "nope")), "FileNotFoundError", "register absent")
t.raises(() => s.register(wd, ["exploded"]), "ArgumentError", "genre inconnu")
s.close()

# mounts
ms := fm.mounts()
t.check(len(ms) >= 1, "mounts")
root := fm.mount_of(tmp)
t.check(root.mount_point != "", "mount_of")
t.check(fm.is_virtual("/proc"), "is_virtual /proc")
t.check(fm.same_mount(tmp, tmp), "same_mount")
t.check(root.usage()["total"] > 0, "usage")
pm := fm.parse_mounts("/dev/sda1 /mnt/mon\\040disque ext4 rw,relatime 0 0\n")
t.eq(pm[0].mount_point, "/mnt/mon disque", "échappement")
t.check(not pm[0].is_readonly() and pm[0].has_option("relatime"), "options")
t.check(len(fm.fs_types()) >= 1, "fs_types")

fs.remove_tree(tmp)
t.summary("filesystem2")
