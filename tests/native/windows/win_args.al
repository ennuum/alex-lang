# Exécutable Windows : arguments reconstruits depuis GetCommandLineW (règles de citation de Microsoft).
use os
for a in os.args():
    print("[" + a + "]")
print(os.argc())
