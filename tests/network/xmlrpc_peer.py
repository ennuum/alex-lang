#!/usr/bin/env python3
"""Pair XML-RPC de référence (bibliothèque standard de Python) pour tests/network/test_xmlrpc.al.

  xmlrpc_peer.py serve           serveur : écrit son port, sert jusqu'à l'appel « stop »
  xmlrpc_peer.py client URL      client : appelle le serveur Alex et écrit les résultats en JSON
"""
import json
import sys
import threading
import xmlrpc.client
from xmlrpc.server import SimpleXMLRPCServer

if sys.argv[1] == "serve":
    srv = SimpleXMLRPCServer(("127.0.0.1", 0), logRequests=False, allow_none=True)
    srv.register_introspection_functions()
    srv.register_multicall_functions()
    srv.register_function(lambda a, b: a + b, "somme")
    srv.register_function(lambda s: s[::-1], "inverse")
    srv.register_function(lambda: {"entier": 7, "réel": 0.5, "liste": [1, "x", None], "vrai": True, "grand": 2 ** 31 - 1}, "types")
    srv.register_function(lambda b: xmlrpc.client.Binary(bytes(reversed(b.data))), "binaire")
    srv.register_function(lambda d: d.value, "date")
    def fail():
        raise xmlrpc.client.Fault(42, "faute voulue")
    srv.register_function(fail, "faute")
    def stop():
        threading.Thread(target=srv.shutdown).start()
        return "arrêt"
    srv.register_function(stop, "stop")
    print(srv.server_address[1], flush=True)
    srv.serve_forever()
else:
    p = xmlrpc.client.ServerProxy(sys.argv[2], allow_none=True)
    out = {}
    out["somme"] = p.somme(2, 3)
    out["echo"] = p.echo({"a": [1, 2.5, "é", None, True]})
    out["methods"] = p.system.listMethods()
    try:
        p.inconnue()
    except xmlrpc.client.Fault as f:
        out["inconnue"] = f.faultCode
    try:
        p.somme(1)
    except xmlrpc.client.Fault as f:
        out["arite"] = f.faultCode
    try:
        p.panne()
    except xmlrpc.client.Fault as f:
        out["panne"] = [f.faultCode, f.faultString]
    m = xmlrpc.client.MultiCall(p)
    m.somme(1, 1)
    m.somme(2, 2)
    out["multi"] = list(m())
    out["bin"] = p.binaire(xmlrpc.client.Binary(b"\x00\x01\xff")).data.hex()
    print(json.dumps(out), flush=True)
