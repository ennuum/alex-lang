# Programme utilisateur : répertoires et noms longs (le même exécutable sous Linux et sous Alex OS).
use io
use os
print("départ :", os.cwd())
os.mkdir("Mes documents")
os.chdir("Mes documents")
print("ici :", os.cwd())
io.write_file("Liste de courses.txt", "pain\nlait\n")
os.mkdir("Archives 2026")
io.write_file("Archives 2026/vieux brouillon.md", "# brouillon\n")
os.chdir("..")
print(io.read_file("Mes documents/Liste de courses.txt"))
print(os.isdir("Mes documents/Archives 2026"), os.isfile("Mes documents/Liste de courses.txt"))
try:
    os.rmdir("Mes documents/Archives 2026")
catch e:
    print(e)
os.remove("Mes documents/Archives 2026/vieux brouillon.md")
os.rmdir("Mes documents/Archives 2026")
print(os.exists("Mes documents/Archives 2026"))
