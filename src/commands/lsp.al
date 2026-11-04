# ALEX — commands.lsp
#
# `alexc lsp [--jsonl] [dossier]` : serveur de langage (LSP 3.17 sur stdin / stdout, en-têtes Content-Length ; avec
# --jsonl, un message JSON par ligne, le mode d'ALEX Studio), comme alex::tooling::runLspServer (LspServer.cpp), sur
# le service de langage écrit en ALEX (commands.lang_service).
#
#   use commands.lsp as cl
#   code := cl.run(["--jsonl", "/chemin/projet"], "stdlib")
#
# Erreurs : aucune levée (erreurs JSON-RPC renvoyées au client).

from core use len, type, to_int
from collections use append
use string as _s
use os as _os
use _native_fd as _fd
use commands.common as cc
use commands.lang_service as ls

func _hex(c):
    if c >= 48 and c <= 57:
        return c - 48
    if c >= 97 and c <= 102:
        return c - 87
    if c >= 65 and c <= 70:
        return c - 55
    return -1

# URI file:// -> chemin. Windows : file:///D:/a/b.al et file:///d%3A/a/b.al -> D:\a\b.al ; file://serveur/partage/x
# -> \\serveur\partage\x (UNC) ; file://D:\a\b.al (forme non standard) accepté tel quel.
func uri_to_path(uri):
    p := _uri_decode(uri)
    if _os.platform() != "windows":
        return p
    if ls.starts_with(uri, "file://") and not ls.starts_with(uri, "file:///") and not (ls.blen(p) >= 2 and ls.bat(p, 1) == 58):
        p = "//" + p
    elif ls.blen(p) >= 3 and ls.bat(p, 0) == 47 and ls.bat(p, 2) == 58:
        p = ls.bsub(p, 1, ls.blen(p))
    return _s.replace(p, "/", "\\")

func _uri_decode(uri):
    s := uri
    if ls.starts_with(s, "file://"):
        s = ls.bsub(s, 7, ls.blen(s))
    b := _s.byte_unpack(s)
    out := []
    i := 0
    n := len(b)
    while i < n:
        if b[i] == 37 and i + 2 < n and _hex(b[i + 1]) >= 0 and _hex(b[i + 2]) >= 0:
            append(out, _hex(b[i + 1]) * 16 + _hex(b[i + 2]))
            i += 3
            continue
        append(out, b[i])
        i += 1
    return _s.byte_pack(out)

# Chemin -> URI file://. Windows : D:\a\b.al -> file:///D:/a/b.al ; \\serveur\partage\x -> file://serveur/partage/x.
func path_to_uri(path):
    hx := "0123456789ABCDEF"
    out := []
    prefix := "file://"
    if _os.platform() == "windows":
        path = _s.replace(path, "\\", "/")
        if ls.starts_with(path, "//"):
            path = ls.bsub(path, 2, ls.blen(path))
        elif ls.blen(path) >= 2 and ls.bat(path, 1) == 58:
            prefix = "file:///"
    for c in _s.byte_unpack(prefix):
        append(out, c)
    for c in _s.byte_unpack(path):
        if (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 47 or c == 45 or c == 95 or c == 46 or c == 126 or c == 58 or c >= 128:
            append(out, c)
        else:
            append(out, 37)
            append(out, ls.bat(hx, c >> 4))
            append(out, ls.bat(hx, c & 15))
    return _s.byte_pack(out)

# ------------------------------------------------------------------------------------------------ transport

class Transport:
    func init(jsonl):
        self.jsonl = jsonl
        self.buf = ""
        self.eof = false

    func _complete():
        if self.jsonl:
            return ls.bfind(self.buf, "\n") >= 0
        return ls.bfind(self.buf, "\r\n\r\n") >= 0

    func _fill(timeout):
        if self.eof:
            return false
        chunk := _fd.read(0, 65536, timeout)
        if chunk == null:
            return false
        if type(chunk) != "str" or chunk == "":
            self.eof = true
            return true
        self.buf = self.buf + chunk
        return true

    func wait_readable(ms):
        if self._complete() or self.eof:
            return true
        return self._fill(ms / 1000.0)

    # Message complet suivant, null en fin de flux.
    func read():
        while true:
            if self.jsonl:
                nl := ls.bfind(self.buf, "\n")
                if nl >= 0:
                    body := ls.bsub(self.buf, 0, nl)
                    self.buf = ls.bsub(self.buf, nl + 1, ls.blen(self.buf))
                    if ls.ends_with(body, "\r"):
                        body = ls.bsub(body, 0, ls.blen(body) - 1)
                    if body == "":
                        continue
                    return body
            else:
                he := ls.bfind(self.buf, "\r\n\r\n")
                if he >= 0:
                    ln := 0
                    have := false
                    for line in _s.split(ls.bsub(self.buf, 0, he), "\r\n"):
                        c := ls.bfind(line, ":")
                        if c >= 0 and ls.lower(ls.bsub(line, 0, c)) == "content-length":
                            ln = to_int(ls.trim(ls.bsub(line, c + 1, ls.blen(line))))
                            have = true
                    if not have:
                        self.buf = ls.bsub(self.buf, he + 4, ls.blen(self.buf))
                        continue
                    if ls.blen(self.buf) >= he + 4 + ln:
                        body := ls.bsub(self.buf, he + 4, he + 4 + ln)
                        self.buf = ls.bsub(self.buf, he + 4 + ln, ls.blen(self.buf))
                        return body
            if self.eof:
                return null
            self._fill(null)

    func write(msg):
        body := cc.json_dump(msg)
        data := body + "\n" if self.jsonl else "Content-Length: " + str(ls.blen(body)) + "\r\n\r\n" + body
        _fd.write(1, data, null)

# ------------------------------------------------------------------------------------------------ conversions

const _COMPLETION_KIND := {"module": 9, "class": 7, "struct": 22, "interface": 8, "enum": 13, "variant": 20, "function": 3,
    "method": 2, "field": 5, "variable": 6, "constant": 21, "parameter": 6, "builtin": 3, "keyword": 14, "snippet": 15}
const _SYMBOL_KIND := {"module": 2, "class": 5, "struct": 23, "interface": 11, "enum": 10, "variant": 22, "function": 12,
    "method": 6, "field": 8, "variable": 13, "constant": 14, "parameter": 13, "builtin": 12, "keyword": 20, "snippet": 20}

func _get(j, dotted):
    cur := j
    for part in _s.split(dotted, "."):
        if type(cur) != "dict" or not (part in cur):
            return null
        cur = cur[part]
    return cur

func _str(v, default=""):
    return v if type(v) == "str" else default

func _int(v, default=0):
    if type(v) == "int":
        return v
    if type(v) == "float":
        return to_int(v)
    return default

func _bool(v, default):
    if type(v) == "bool":
        return v
    return default

class LspError:
    func init(code, message):
        self.code = code
        self.message = message

func _seqlen(c):
    return 1 if c < 128 else (2 if c < 224 else (3 if c < 240 else 4))

class Server:
    func init(stdlib, ws, jsonl):
        self.io = Transport(jsonl)
        self.svc = ls.LanguageService(stdlib, ws)
        self.utf8 = false
        self.utf16 = true
        self.shutdown = false
        self.exit = false
        self.initialized = false
        self.dirty = {}
        self.uri_of = {}
        self.uri_order = []

    func run():
        while true:
            if len(self.dirty) > 0 and not self.io.wait_readable(120):
                self.flush_diagnostics()
                continue
            body := self.io.read()
            if body == null:
                break
            msg := null
            ok := true
            try:
                msg = cc.json_parse(body)
            catch e:
                ok = false
                self.io.write({"jsonrpc": "2.0", "id": null, "error": {"code": -32700, "message": e.message}})
            if not ok:
                continue
            self.dispatch(msg)
            if self.exit:
                break
        return 0 if self.shutdown else 1

    # -------- colonnes : octets UTF-8 <-> unités UTF-16 (ou points de code)
    func line_of(path, line):
        fi := self.svc.index(path)
        if line < 0 or line >= len(fi.lines):
            return ""
        return fi.lines[line]

    func to_byte(path, line, col):
        if self.utf8:
            return col
        t := _s.byte_unpack(self.line_of(path, line))
        n := len(t)
        i := 0
        u := 0
        while i < n and u < col:
            l := _seqlen(t[i])
            if self.utf16:
                u += 2 if l == 4 else 1
            else:
                u += 1
            i += l
        return (i if i < n else n) + (col - u if u < col else 0)

    func from_byte(path, line, bcol):
        if self.utf8:
            return bcol
        t := _s.byte_unpack(self.line_of(path, line))
        n := len(t)
        u := 0
        i := 0
        while i < n and i < bcol:
            l := _seqlen(t[i])
            u += 2 if (self.utf16 and l == 4) else 1
            i += l
        if bcol > n:
            u += bcol - n
        return u

    func pos(path, line, bcol):
        return {"line": line, "character": self.from_byte(path, line, bcol)}

    func range(path, r):
        return {"start": self.pos(path, r[0], r[1]), "end": self.pos(path, r[2], r[3])}

    func range_from(path, j):
        l := _int(_get(j, "start.line"))
        el := _int(_get(j, "end.line"))
        return [l, self.to_byte(path, l, _int(_get(j, "start.character"))), el, self.to_byte(path, el, _int(_get(j, "end.character")))]

    func uri_for(path):
        c := ls.canonical(path)
        return self.uri_of[c] if c in self.uri_of else path_to_uri(path)

    func location(loc):
        return {"uri": self.uri_for(loc[0]), "range": self.range(loc[0], loc[1])}

    func workspace_edit(changes):
        out := {}
        for fc in changes:
            out[self.uri_for(fc[0])] = [{"range": self.range(fc[0], e[0]), "newText": e[1]} for e in fc[1]]
        return {"changes": out}

    func diagnostic_json(path, d):
        j := {"range": self.range(path, d.range), "severity": d.severity}
        if d.code != "":
            j["code"] = d.code
        j["source"] = d.source
        j["message"] = d.message
        if len(d.tags) > 0:
            tags := []
            for t in d.tags:
                if t == "unnecessary":
                    append(tags, 1)
                if t == "deprecated":
                    append(tags, 2)
            j["tags"] = tags
        return j

    func publish(path):
        arr := []
        if self.svc.is_open(path):
            for d in self.svc.diagnostics(path):
                append(arr, self.diagnostic_json(path, d))
        self.notify("textDocument/publishDiagnostics", {"uri": self.uri_for(path), "diagnostics": arr})

    func flush_diagnostics():
        files := cc.sort_strings([f for f in self.dirty])
        self.dirty = {}
        for f in files:
            self.publish(f)

    func notify(method, params):
        self.io.write({"jsonrpc": "2.0", "method": method, "params": params})

    func reply(id, result):
        self.io.write({"jsonrpc": "2.0", "id": id, "result": result})

    func reply_error(id, code, message):
        self.io.write({"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}})

    func doc_path(params):
        return ls.canonical(uri_to_path(_str(_get(params, "textDocument.uri"))))

    func remember_uri(params):
        uri := _str(_get(params, "textDocument.uri"))
        c := ls.canonical(uri_to_path(uri))
        if not (c in self.uri_of):
            append(self.uri_order, c)
        self.uri_of[c] = uri

    func dispatch(msg):
        if type(msg) != "dict":
            return
        method := _str(msg["method"] if "method" in msg else null)
        is_request := ("id" in msg) and method != ""
        id := msg["id"] if "id" in msg else null
        params := msg["params"] if "params" in msg else null
        if method == "":
            return
        try:
            if self.shutdown and method != "exit":
                if is_request:
                    self.reply_error(id, -32600, "serveur arrêté")
                return
            if method == "initialize":
                self.reply(id, self.initialize(params))
                self.initialized = true
                return
            if method == "initialized":
                return
            if method == "shutdown":
                self.shutdown = true
                self.reply(id, null)
                return
            if method == "exit":
                self.exit = true
                return
            if not self.initialized and is_request:
                self.reply_error(id, -32002, "serveur non initialisé")
                return
            if method == "textDocument/didOpen":
                self.remember_uri(params)
                p := self.doc_path(params)
                self.svc.open(p, _str(_get(params, "textDocument.text")), _int(_get(params, "textDocument.version")))
                self.dirty[p] = true
                return
            if method == "textDocument/didChange":
                p := self.doc_path(params)
                changes := _get(params, "contentChanges")
                text := self.svc.text_of(p)
                version := _int(_get(params, "textDocument.version"))
                for c in (changes if type(changes) == "list" else []):
                    if type(c) != "dict" or not ("range" in c):
                        text = _str(_get(c, "text"))
                    else:
                        r := self.range_from(p, c["range"])
                        lines := cc.split_lines(text)
                        a := self._offset(lines, text, r[0], r[1])
                        b := self._offset(lines, text, r[2], r[3])
                        text = ls.bsub(text, 0, a) + _str(c["text"] if "text" in c else "") + ls.bsub(text, a if a > b else b, ls.blen(text))
                        self.svc.change(p, text, version)
                self.svc.change(p, text, version)
                self.dirty[p] = true
                return
            if method == "textDocument/didClose":
                p := self.doc_path(params)
                self.svc.close(p)
                if p in self.dirty:
                    nd := {}
                    for k in self.dirty:
                        if k != p:
                            nd[k] = true
                    self.dirty = nd
                self.publish(p)
                return
            if method == "textDocument/didSave":
                p := self.doc_path(params)
                if type(params) == "dict" and ("text" in params):
                    self.svc.change(p, _str(params["text"]))
                for path in self.uri_order:
                    if self.svc.is_open(path):
                        self.dirty[path] = true
                return
            if method == "workspace/didChangeWatchedFiles" or method == "workspace/didChangeConfiguration" or method == "$/cancelRequest" or method == "$/setTrace":
                if method == "workspace/didChangeWatchedFiles":
                    for path in self.uri_order:
                        if self.svc.is_open(path):
                            self.dirty[path] = true
                return
            if not is_request:
                return
            self.reply(id, self.request(method, params))
        catch e:
            if is_request:
                if e.type == "LspMethodNotFound":
                    self.reply_error(id, -32601, e.message)
                elif e.type == "LspError":
                    self.reply_error(id, -32603, e.message)
                else:
                    self.reply_error(id, -32603, str(e))

    func _offset(lines, text, line, col):
        off := 0
        i := 0
        while i < line and i < len(lines):
            off += ls.blen(lines[i]) + 1
            i += 1
        v := off + col
        return v if v < ls.blen(text) else ls.blen(text)

    func initialize(params):
        enc := _get(params, "capabilities.general.positionEncodings")
        chosen := "utf-16"
        for e in (enc if type(enc) == "list" else []):
            if e == "utf-32":
                chosen = "utf-32"
        for e in (enc if type(enc) == "list" else []):
            if e == "utf-8":
                chosen = "utf-8"
        self.utf16 = chosen == "utf-16"
        self.utf8 = chosen == "utf-8"
        root := uri_to_path(params["rootUri"]) if type(params) == "dict" and ("rootUri" in params) and type(params["rootUri"]) == "str" else _str(_get(params, "rootPath"))
        wf := _get(params, "workspaceFolders")
        if type(wf) == "list" and len(wf) > 0:
            root = uri_to_path(_str(_get(wf[0], "uri")))
        if root != "":
            self.svc.set_workspace_root(root)
        caps := {"positionEncoding": chosen,
                 "textDocumentSync": {"openClose": true, "change": 1, "save": {"includeText": false}},
                 "completionProvider": {"triggerCharacters": ["."], "resolveProvider": false},
                 "hoverProvider": true,
                 "signatureHelpProvider": {"triggerCharacters": ["(", ","]},
                 "definitionProvider": true, "referencesProvider": true, "documentHighlightProvider": true,
                 "documentSymbolProvider": true, "workspaceSymbolProvider": true, "documentFormattingProvider": true,
                 "renameProvider": {"prepareProvider": true},
                 "codeActionProvider": {"codeActionKinds": ["quickfix", "source.organizeImports"]}}
        return {"capabilities": caps, "serverInfo": {"name": "alex-lsp", "version": _os.alex_build()["version"]}}

    func position(params):
        path := self.doc_path(params)
        line := _int(_get(params, "position.line"))
        c := _int(_get(params, "position.character"))
        return [path, line, c if self.utf8 else self.to_byte(path, line, c)]

    func doc_symbol(path, s):
        j := {"name": s["name"]}
        if s["detail"] != "":
            j["detail"] = s["detail"]
        j["kind"] = _SYMBOL_KIND[s["kind"]] if s["kind"] in _SYMBOL_KIND else 13
        j["range"] = self.range(path, s["range"])
        j["selectionRange"] = self.range(path, s["selection"])
        if len(s["children"]) > 0:
            j["children"] = [self.doc_symbol(path, c) for c in s["children"]]
        return j

    func request(method, params):
        if len(self.dirty) > 0 and method != "textDocument/completion":
            self.flush_diagnostics()
        svc := self.svc
        if method == "textDocument/completion":
            p := self.position(params)
            items := []
            for it in svc.complete(p[0], p[1], p[2]):
                j := {"label": it["label"], "kind": _COMPLETION_KIND[it["kind"]] if it["kind"] in _COMPLETION_KIND else 1}
                if it["detail"] != "":
                    j["detail"] = it["detail"]
                if it["doc"] != "":
                    j["documentation"] = {"kind": "markdown", "value": it["doc"]}
                if it["insert"] != "":
                    j["insertText"] = it["insert"]
                j["insertTextFormat"] = 2 if it["snippet"] else 1
                if it["sort"] != "":
                    j["sortText"] = it["sort"]
                append(items, j)
                if len(items) >= 500:
                    break
            return {"isIncomplete": false, "items": items}
        if method == "textDocument/hover":
            p := self.position(params)
            h := svc.hover(p[0], p[1], p[2])
            if h == null:
                return null
            return {"contents": {"kind": "markdown", "value": h["markdown"]}, "range": self.range(p[0], h["range"])}
        if method == "textDocument/signatureHelp":
            p := self.position(params)
            s := svc.signature_help(p[0], p[1], p[2])
            if s == null:
                return null
            sig := {"label": s["label"]}
            if s["doc"] != "":
                sig["documentation"] = {"kind": "markdown", "value": s["doc"]}
            sig["parameters"] = [{"label": x} for x in s["params"]]
            return {"signatures": [sig], "activeSignature": 0, "activeParameter": s["active"]}
        if method == "textDocument/definition" or method == "textDocument/declaration":
            p := self.position(params)
            return [self.location(l) for l in svc.definition(p[0], p[1], p[2])]
        if method == "textDocument/references":
            p := self.position(params)
            incl := _bool(_get(params, "context.includeDeclaration"), true)
            return [self.location(l) for l in svc.references(p[0], p[1], p[2], incl)]
        if method == "textDocument/documentHighlight":
            p := self.position(params)
            return [{"range": self.range(p[0], r), "kind": 1} for r in svc.highlights(p[0], p[1], p[2])]
        if method == "textDocument/prepareRename":
            p := self.position(params)
            r := svc.prepare_rename(p[0], p[1], p[2])
            if r == null:
                return null
            return {"range": self.range(p[0], r[0]), "placeholder": r[1]}
        if method == "textDocument/rename":
            p := self.position(params)
            r := svc.rename(p[0], p[1], p[2], _str(_get(params, "newName")))
            if r[0] == null:
                raise("LspError", "renommage impossible" if r[1] == "" else r[1])
            return self.workspace_edit(r[0])
        if method == "textDocument/documentSymbol":
            path := self.doc_path(params)
            return [self.doc_symbol(path, s) for s in svc.document_symbols(path)]
        if method == "workspace/symbol":
            arr := []
            for s in svc.workspace_symbols(_str(_get(params, "query"))):
                j := {"name": s["name"], "kind": _SYMBOL_KIND[s["kind"]] if s["kind"] in _SYMBOL_KIND else 13}
                if s["container"] != "":
                    j["containerName"] = s["container"]
                j["location"] = self.location([s["file"], s["range"]])
                append(arr, j)
            return arr
        if method == "textDocument/formatting":
            path := self.doc_path(params)
            tab := _int(_get(params, "options.tabSize"), 4)
            return [{"range": self.range(path, e[0]), "newText": e[1]} for e in svc.format(path, tab)]
        if method == "textDocument/codeAction":
            path := self.doc_path(params)
            r := self.range_from(path, _get(params, "range"))
            ctx := []
            dl := _get(params, "context.diagnostics")
            for dj in (dl if type(dl) == "list" else []):
                ctx_r := self.range_from(path, _get(dj, "range"))
                append(ctx, {"range": ctx_r, "code": _str(_get(dj, "code")), "message": _str(_get(dj, "message")), "severity": _int(_get(dj, "severity"), 1)})
            arr := []
            for a in svc.code_actions(path, r, ctx):
                j := {"title": a["title"], "kind": a["kind"]}
                if a["preferred"]:
                    j["isPreferred"] = true
                j["edit"] = self.workspace_edit(a["changes"])
                append(arr, j)
            return arr
        raise("LspMethodNotFound", "méthode inconnue : " + method)

func run(args, stdlib):
    ws := _os.cwd()
    jsonl := false
    for a in args:
        if a == "--jsonl":
            jsonl = true
        elif not ls.starts_with(a, "--"):
            ws = a
    return Server(stdlib, ws, jsonl).run()
