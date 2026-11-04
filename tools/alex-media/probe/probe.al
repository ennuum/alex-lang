# alex-media probe : décrit des fichiers multimédias (texte ou JSON), éventuellement dans un processus isolé.
#   alex run tools/alex-media/alex-media.al -- probe [--json] [--isolated] fichier...
from core use len
from collections use keys
use os
use json
use multimedia.container.probe as probe
use multimedia.security.sandbox as msb

func main(args):
    as_json := false
    isolated := false
    files := []
    for a in args:
        if a == "--json":
            as_json = true
        elif a == "--isolated":
            isolated = true
        elif a == "-h" or a == "--help":
            print("usage : alex-media probe [--json] [--isolated] fichier...")
            return 0
        else:
            files = files + [a]
    if len(files) == 0:
        print("alex-media probe : aucun fichier (voir --help)")
        return 2
    code := 0
    for f in files:
        if isolated:
            r := msb.isolated_probe(f)
            if as_json:
                print(json.stringify(r))
            elif r["ok"]:
                print(f + " : " + str(r["info"]["container"]) + ", " + str(len(r["info"]["streams"])) + " piste(s) (analyse isolée)")
            else:
                print(f + " : ERREUR " + str(r["error_type"]) + " : " + str(r["error"]))
                code = 1
            continue
        try:
            i := probe.probe(f)
            if as_json:
                print(json.stringify(i.to_dict()))
            else:
                print(f + " : " + i.describe())
                for s in i.streams:
                    print("  " + s.describe())
                for k in keys(i.tags):
                    print("  " + str(k) + " = " + str(i.tags[k]))
                for w in i.warnings:
                    print("  ! " + w)
        catch e:
            print(f + " : ERREUR " + e.type + " : " + e.message)
            code = 1
    return code
