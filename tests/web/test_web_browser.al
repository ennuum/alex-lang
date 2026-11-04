# ALEX - tests du paquet web.browser. Lancer depuis la racine : ./alex run tests/web/test_web_browser.al
use testing
use web.browser as wb
use web.browser.timers as tm
use web.browser.animation_frame as af
use web.browser.console as cs
use web.browser.fetch as ft
use web.browser.request as rq
use web.browser.response as rs
use web.browser.abort_controller as ac
use web.browser.local_storage as ls
use web.browser.session_storage as ss
use web.browser.url_api as ua
use web.browser.url_search_params as usp
use web.browser.form_data as fd
use web.browser.blob as bl
use web.browser.file as fl
use web.browser.file_reader as fr
use web.browser.object_url as ou
use web.browser.permissions as pm
use web.browser.clipboard as cb
use web.browser.notifications as nt
use web.browser.browser_capabilities as caps
use web.browser.browser_errors as be
use web.server.request_dispatch as rd
use web.http.response as hresp
use web.client.http_client as hc
use web.dom as dom
use io
use os
from core use len
from collections use append
from testing use assert_eq, assert_true, assert_false, assert_null, assert_raises

func t_event_loop():
    log := []
    loop := tm.EventLoop()
    loop.set_timeout(() => append(log, "100"), 100)
    loop.set_timeout(() => append(log, "0"), 0)
    loop.queue_microtask(() => append(log, "micro"))
    iv := loop.set_interval(() => append(log, "iv"), 40)
    loop.advance(150)
    loop.clear_interval(iv)
    assert_eq(log, ["micro", "0", "iv", "iv", "100", "iv"])
    assert_eq(loop.now(), 150.0)
    assert_eq(tm.delay(loop, 50, "ok").then((v) => v + " !").wait(), "ok !")
    assert_eq(loop.now(), 200.0)
    assert_eq(tm.all(loop, [tm.resolved(loop, 1), tm.delay(loop, 10, 2), 3]).wait(), [1, 2, 3])
    assert_eq(tm.race(loop, [tm.delay(loop, 30, "lent"), tm.delay(loop, 5, "rapide")]).wait(), "rapide")
    assert_eq(tm.any(loop, [tm.rejected(loop, be.ErrorValue("X", "non")), tm.delay(loop, 5, "oui")]).wait(), "oui")
    settled := tm.all_settled(loop, [tm.resolved(loop, 1), tm.rejected(loop, be.ErrorValue("X", "non"))]).wait()
    assert_eq(settled[1]["status"], "rejected")
    assert_raises(() => tm.Promise(loop, (res, rej) => rej(be.ErrorValue("TypeError", "Failed to fetch"))).wait(), "TypeError")
    assert_eq(tm.resolved(loop, 2).then((v) => 1 / 0).catch_((e) => "rattrapé " + e.name).wait(), "rattrapé ZeroDivisionError")
    assert_eq(tm.resolved(loop, 1).then((v) => tm.delay(loop, 20, v + 1)).then((v) => v * 10).wait(), 20)
    fin := []
    tm.resolved(loop, 1).finally_(() => append(fin, "fin")).wait()
    assert_eq(fin, ["fin"])
    order := []
    tm.resolved(loop, 0).then((v) => append(order, "then"))
    loop.queue_task(() => append(order, "task"))
    loop.queue_microtask(() => append(order, "micro"))
    loop.run_until_idle()
    assert_eq(order, ["then", "micro", "task"])
    frames := []
    loop.request_animation_frame((t) => append(frames, t))
    loop.request_animation_frame((t) => append(frames, t))
    loop.advance(20)
    assert_eq(len(frames), 2)
    assert_eq(frames[0], frames[1])
    vals := []
    a := af.animate(loop, 100, (p) => append(vals, p))
    loop.advance(200)
    assert_true(a.finished)
    assert_eq(vals[len(vals) - 1], 1.0)
    nest := [0]
    t0 := loop.now()
    loop.set_timeout(() => _again(loop, nest), 0)
    loop.run_until_idle()
    assert_eq(nest[0], 10)
    assert_eq(loop.now() - t0, 20.0)
    loop.set_timeout(() => 1 / 0, 0)
    loop.run_until_idle()
    assert_eq(loop.errors[len(loop.errors) - 1][0], "ZeroDivisionError")
    assert_raises(() => tm.Promise(loop).wait(100), "TimeoutError")

func _again(loop, nest):
    nest[0] = nest[0] + 1
    if nest[0] < 10:
        loop.set_timeout(() => _again(loop, nest), 0)

testing.test("boucle d'événements et promesses", t_event_loop)

func t_console():
    c := cs.Console()
    c.log("Bonjour %s, %d ans", "Ada", 36.7)
    c.warn({"a": [1, "x"]})
    c.group("Réseau")
    c.info("GET /")
    c.group_end()
    c.count("clic")
    c.count("clic")
    c.assert_(1 == 2, "faux")
    c.table([{"nom": "Ada", "âge": 36}, {"nom": "Bob"}])
    assert_eq(c.messages[0].text, "Bonjour Ada, 36 ans")
    assert_eq(c.messages[1].text, "{a: [1, 'x']}")
    assert_eq(c.messages[3].group_depth, 1)
    assert_eq(c.messages[5].text, "clic: 2")
    assert_eq(len(c.errors()), 1)
    assert_eq(c.errors()[0].text, "Assertion failed: faux")
    assert_true("│ (index) │ nom   │ âge │" in c.messages[7].text)

testing.test("console", t_console)

func _router():
    r := rd.Router()
    r.get("/api/salut", (req) => hresp.json({"cookie": req.headers.get("cookie")}))
    r.get("/login", (req) => hresp.text("ok", 200, {"Set-Cookie": "sid=abc; Path=/"}))
    r.post("/echo", (req) => hresp.text(req.text(), 201, {"Content-Type": req.headers.get("content-type")}))
    return r

func t_fetch():
    loop := tm.EventLoop()
    net := ft.Network(loop, hc.CookieJar())
    net.mock("https://api.test/notes", (req) => {"notes": [1, 2]})
    net.mock("/bonjour", (req) => "Bonjour")
    net.mock("https://api.test/vieux", (req) => (301, "", {"Location": "/notes"}))
    net.mock("https://autre.test/data", (req) => (200, "partagé", {"Access-Control-Allow-Origin": "https://app.test"}))
    net.mock("https://autre.test/prive", (req) => "x")
    net.route("https://app.test", _router())
    r := ft.fetch(net, "https://api.test/notes").wait()
    assert_eq(r.status, 200)
    assert_true(r.ok)
    assert_eq(r.json().wait(), {"notes": [1, 2]})
    assert_raises(() => r.text().wait(), "TypeError")
    assert_eq(ft.fetch(net, "https://x.test/bonjour").wait().text().wait(), "Bonjour")
    r2 := ft.fetch(net, "https://api.test/vieux").wait()
    assert_true(r2.redirected)
    assert_eq(r2.url, "https://api.test/notes")
    ctx := ft.FetchContext("https://app.test/page", null, "https://app.test")
    assert_eq(ft.fetch(net, "https://autre.test/data", null, ctx).wait().type, "cors")
    assert_raises(() => ft.fetch(net, "https://autre.test/prive", null, ctx).wait(), "TypeError")
    assert_eq(ft.fetch(net, "https://autre.test/prive", {"mode": "no-cors"}, ctx).wait().type, "opaque")
    ft.fetch(net, "/login", null, ctx).wait()
    assert_eq(ft.fetch(net, "/api/salut", null, ctx).wait().json().wait(), {"cookie": "sid=abc"})
    echo := ft.fetch(net, "/echo", {"method": "POST", "json": {"a": 1}}, ctx).wait()
    assert_eq(echo.status, 201)
    assert_eq(echo.text().wait(), "{\"a\":1}")
    assert_eq(echo.headers.get("content-type"), "application/json")
    assert_raises(() => ft.fetch(net, "https://nulle.part/").wait(), "TypeError")
    ctl := ac.AbortController()
    net.latency = 100
    p := ft.fetch(net, "https://api.test/notes", {"signal": ctl.signal})
    loop.set_timeout(() => ctl.abort(), 10)
    assert_raises(() => p.wait(), "AbortError")
    assert_raises(() => ft.fetch(net, "https://api.test/notes", {"signal": ac.timeout(loop, 20)}).wait(), "TimeoutError")
    net.latency = 0
    assert_eq(ft.fetch(net, "data:text/plain;base64,Qm9uam91cg==").wait().text().wait(), "Bonjour")
    u := ou.create_object_url(bl.Blob(["<b>x</b>"], {"type": "text/html"}), "https://app.test")
    rb := ft.fetch(net, u).wait()
    assert_eq(rb.headers.get("content-type"), "text/html")
    ou.revoke_object_url(u)
    assert_raises(() => ft.fetch(net, u).wait(), "TypeError")
    assert_raises(() => rq.Request("/x", {"method": "GET", "body": "a"}), "TypeError")
    assert_raises(() => rq.Request("/x", {"method": "TRACE"}), "TypeError")
    h := rq.Headers({"Accept": "text/html"})
    h.append("accept", "application/json")
    assert_eq(h.get("ACCEPT"), "text/html, application/json")
    assert_eq(rs.json_response({"a": 1}).headers.get("content-type"), "application/json")
    assert_eq(rs.redirect("/ailleurs", 302).headers.get("location"), "/ailleurs")
    assert_eq(rs.error().type, "error")
    assert_raises(() => rs.Response("x", {"status": 204}), "TypeError")
    assert_raises(() => rs.Response("x", {"status": 99}), "RangeError")
    assert_eq(net.log[0], ("GET", "https://api.test/notes", 200))

testing.test("fetch, Request, Response, annulation", t_fetch)

func t_storage():
    st := ls.Storage("https://exemple.org", 40)
    st.set_item("a", "1")
    assert_eq(st.get_item("a"), "1")
    assert_eq(st.length(), 1)
    assert_eq(st.key(0), "a")
    assert_raises(() => st.set_item("long", "xxxxxxxxxxxxxxxxxxxxxxx"), "QuotaExceededError")
    st.remove_item("a")
    assert_null(st.get_item("a"))
    path := os.join(os.tmp_dir(), "alex_test_storage_" + str(os.pid()) + ".json")
    p1 := ls.Storage("https://exemple.org", 5242880, path)
    p1.set_item("theme", "sombre")
    p2 := ls.Storage("https://exemple.org", 5242880, path)
    assert_eq(p2.get_item("theme"), "sombre")
    os.remove(path)
    sess := ss.SessionStorageArea()
    sess.for_origin("https://a.test").set_item("panier", "[1]")
    copie := sess.clone()
    assert_eq(copie.for_origin("https://a.test").get_item("panier"), "[1]")
    copie.for_origin("https://a.test").set_item("panier", "[2]")
    assert_eq(sess.for_origin("https://a.test").get_item("panier"), "[1]")

testing.test("stockage local et de session", t_storage)

func t_url_forms_files():
    u := ua.URL("/recherche?q=chat#res", "https://exemple.org/a/b")
    assert_eq(u.href(), "https://exemple.org/recherche?q=chat#res")
    assert_eq(u.origin(), "https://exemple.org")
    u.search_params.append("page", 2)
    assert_eq(u.search(), "?q=chat&page=2")
    u.set_hash("")
    u.set_pathname("/autre")
    assert_eq(u.href(), "https://exemple.org/autre?q=chat&page=2")
    u.set_search("x=1")
    assert_eq(u.search_params.get("x"), "1")
    assert_false(ua.can_parse("pas une url"))
    assert_null(ua.parse("::"))
    assert_raises(() => ua.URL("::"), "TypeError")
    p := usp.URLSearchParams("?q=chat+noir&page=2")
    assert_eq(p.get("q"), "chat noir")
    p.append("tag", "a")
    p.append("tag", "b")
    p.set("page", 3)
    p.delete("tag", "a")
    assert_eq(p.to_string(), "q=chat+noir&page=3&tag=b")
    p.sort()
    assert_eq(p.keys(), ["page", "q", "tag"])
    doc := dom.parse("<!DOCTYPE html><form><input name=nom value=Ada><input type=checkbox name=c checked><select name=s><option>A<option selected>B</select><input type=file name=f></form>")
    data := fd.from_form(doc.query_selector("form"))
    assert_eq(data.get("nom"), "Ada")
    assert_eq(data.get("s"), "B")
    assert_true(data.has_files())
    fl.set_input_files(doc.query_selector("input[type=file]"), [fl.File(["contenu"], "a.txt")])
    data2 := fd.from_form(doc.query_selector("form"))
    assert_eq(data2.get("f").name, "a.txt")
    mp := data2.to_multipart("FRONTIERE")
    assert_eq(mp[1], "multipart/form-data; boundary=FRONTIERE")
    assert_true("Content-Disposition: form-data; name=\"f\"; filename=\"a.txt\"\r\nContent-Type: text/plain" in mp[0])
    assert_eq(data2.to_urlencoded(), "nom=Ada&c=on&s=B&f=a.txt")
    b := bl.Blob(["Bonjour ", "été"], {"type": "text/plain"})
    assert_eq(b.size, 13)
    assert_eq(b.slice(0, 7).text_now(), "Bonjour")
    assert_eq(b.slice(-5).text_now(), "été")
    assert_eq(b.to_data_url(), "data:text/plain;base64,Qm9uam91ciDDqXTDqQ==")
    assert_eq(bl.from_data_url("data:,a%20b").text_now(), "a b")
    f := fl.File(["a,b"], "donnees.csv")
    assert_eq(f.type, "text/csv")
    loop := tm.EventLoop()
    r := fr.FileReader(loop)
    events := []
    r.add_event_listener("loadstart", (e) => append(events, "start"))
    r.add_event_listener("load", (e) => append(events, "load"))
    r.add_event_listener("loadend", (e) => append(events, "end"))
    r.read_as_text(f)
    assert_eq(r.ready_state, fr.LOADING)
    assert_raises(() => r.read_as_text(f), "InvalidStateError")
    loop.run_until_idle()
    assert_eq(r.result, "a,b")
    assert_eq(events, ["start", "load", "end"])
    assert_eq(fr.read_data_url(loop, f).wait(), "data:text/csv;base64,YSxi")
    path := os.join(os.tmp_dir(), "alex_test_file_" + str(os.pid()) + ".txt")
    io.write_file(path, "disque")
    g := fl.from_path(path)
    assert_eq(g.name, "alex_test_file_" + str(os.pid()) + ".txt")
    assert_eq(g.text_now(), "disque")
    os.remove(path)

testing.test("URL, formulaires, Blob et fichiers", t_url_forms_files)

func t_permissions_apis():
    loop := tm.EventLoop()
    mgr := pm.PermissionManager()
    o := "https://exemple.org"
    assert_eq(mgr.state(o, "notifications"), "prompt")
    perms := pm.Permissions(mgr, o, loop)
    st := perms.query({"name": "geolocation"}).wait()
    changes := []
    st.add_event_listener("change", (e) => append(changes, st.state))
    mgr.deny(o, "geolocation")
    assert_eq(changes, ["denied"])
    assert_raises(() => perms.query({"name": "teleportation"}).wait(), "TypeError")
    data := cb.ClipboardData()
    c := cb.Clipboard(data, mgr, o, loop)
    c.write_text("copié").wait()
    assert_eq(data.text(), "copié")
    assert_raises(() => c.read_text().wait(), "NotAllowedError")
    mgr.grant(o, "clipboard-read")
    assert_eq(c.read_text().wait(), "copié")
    center := nt.NotificationCenter(mgr, o, loop)
    n0 := center.notify("refusée")
    errs := []
    n0.add_event_listener("error", (e) => append(errs, 1))
    loop.run_until_idle()
    assert_eq(len(errs), 1)
    mgr.prompt_answer = "granted"
    assert_eq(center.request_permission().wait(), "granted")
    n := center.notify("Message", {"body": "Ada", "tag": "m"})
    n2 := center.notify("Message 2", {"tag": "m"})
    assert_eq(len(center.visible()), 1)
    clicks := []
    n2.add_event_listener("click", (e) => append(clicks, e.type))
    center.click(n2)
    assert_eq(clicks, ["click"])
    n2.close()
    assert_eq(len(center.visible()), 0)
    p := caps.profile("legacy")
    assert_false(p.css_supports("(gap: 1rem)"))
    assert_false(p.css_supports("(display: grid)"))
    assert_false(p.supports("fetch"))
    assert_true(caps.profile("chrome").css_supports("(display: grid)"))
    d := caps.device("iphone-15")
    assert_eq((d.width, d.height, d.dpr, d.touch), (393, 852, 3, true))
    assert_raises(() => caps.profile("netscape"), "BrowserError")

testing.test("permissions, presse-papiers, notifications, profils", t_permissions_apis)

func _site():
    r := rd.Router()
    r.get("/", (req) => hresp.html("<!DOCTYPE html><title>Accueil</title><h1>Bonjour</h1><form action=/cherche><input name=q><button type=submit>Go</button></form><a id=suite href=/page2>suite</a><a id=ancre href=#bas>bas</a><p id=bas>fin</p>"))
    r.get("/cherche", (req) => hresp.html("<!DOCTYPE html><title>Résultats</title><p id=r>" + req.query_param("q") + "</p>"))
    r.get("/page2", (req) => hresp.html("<!DOCTYPE html><title>Page 2</title><p>deux</p>", 200, {"Set-Cookie": "vu=1; Path=/"}))
    r.post("/envoi", (req) => hresp.html("<!DOCTYPE html><title>Merci</title><p>" + req.form().get("nom") + "</p>"))
    r.get("/api/heure", (req) => hresp.json({"h": 12}))
    return r

func t_browser():
    b := wb.Browser()
    b.route("https://app.test", _site())
    tab := b.new_tab(null, "iphone-15")
    loaded := []
    tab.on_load = [(t, d, w) => append(loaded, d.title())]
    tab.goto("https://app.test/")
    assert_eq(tab.title(), "Accueil")
    assert_eq(tab.window.inner_width, 393)
    assert_eq(tab.window.navigator.max_touch_points, 5)
    assert_true(tab.window.match_media("(pointer: coarse)").matches())
    tab.fill("input[name=q]", "chat noir")
    tab.click("button")
    tab.wait_for_navigation()
    assert_eq(tab.url.href(), "https://app.test/cherche?q=chat+noir")
    assert_eq(tab.query("#r").text_content(), "chat noir")
    assert_eq(tab.window.history.length(), 2)
    tab.window.history.back()
    b.idle()
    assert_eq(tab.title(), "Accueil")
    hashes := []
    tab.window.add_event_listener("hashchange", (e) => append(hashes, e.new_url))
    tab.click("#ancre")
    b.idle()
    assert_eq(tab.url.href(), "https://app.test/#bas")
    assert_eq(hashes, ["https://app.test/#bas"])
    assert_true(tab.query("#bas").matches(":target"))
    pops := []
    tab.window.add_event_listener("popstate", (e) => append(pops, e.state))
    tab.window.history.push_state({"p": 2}, "", "?p=2")
    assert_eq(tab.window.location.search(), "?p=2")
    tab.window.history.back()
    b.idle()
    assert_eq(pops, [null])
    assert_raises(() => tab.window.history.push_state(null, "", "https://ailleurs.test/"), "SecurityError")
    tab.click("#suite")
    tab.wait_for_navigation()
    assert_eq(tab.title(), "Page 2")
    assert_eq(tab.cookie(), "vu=1")
    tab.set_cookie("theme=sombre; path=/")
    assert_eq(tab.cookie(), "vu=1; theme=sombre")
    tab.set_cookie("secret=1; HttpOnly")
    assert_eq(b.cookies(), {"vu": "1", "theme": "sombre"})
    tab.window.local_storage.set_item("k", "v")
    tab2 := b.new_tab("https://app.test/")
    seen := []
    tab2.window.add_event_listener("storage", (e) => append(seen, e.key + "=" + e.new_value))
    tab.window.local_storage.set_item("k2", "v2")
    b.idle()
    assert_eq(seen, ["k2=v2"])
    assert_eq(tab2.window.local_storage.get_item("k"), "v")
    assert_eq(loaded, ["Accueil", "Résultats", "Page 2"])
    assert_eq(tab.fetch("/api/heure").wait().json().wait(), {"h": 12})
    tab.load_html("<!DOCTYPE html><form method=post action='https://app.test/envoi'><input name=nom value=Ada><button>OK</button></form>", "https://app.test/form")
    tab.click("button")
    tab.wait_for_navigation()
    assert_eq(tab.text(), "Ada")
    tab.window.set_timeout(() => tab.console.log("après %d ms", 500), 500)
    b.run(600)
    assert_eq(tab.console.messages[len(tab.console.messages) - 1].text, "après 500 ms")
    obs_log := []
    obs := dom.observe_mutations(tab.document.body(), (recs, o) => append(obs_log, len(recs)))
    tab.document.body().append_child(tab.document.create_element("div"))
    assert_eq(obs_log, [])
    b.idle()
    assert_eq(obs_log, [1])
    vis := []
    tab.document.add_event_listener("visibilitychange", (e) => append(vis, tab.document.visibility_state))
    tab.window.visibility.hide()
    tab.window.visibility.show()
    assert_eq(vis, ["hidden", "visible"])
    fsm := tab.window.fullscreen
    el := tab.query("p")
    fsm.request(el).wait()
    assert_true(el.matches(":fullscreen"))
    fsm.exit().wait()
    assert_false(el.matches(":fullscreen"))
    tab.window.navigator.set_online(false)
    assert_raises(() => tab.fetch("/api/heure").wait(), "TypeError")
    tab.window.navigator.set_online(true)
    assert_raises(() => tab.goto("https://ailleurs.test/"), "TypeError")
    assert_eq(tab.title(), "Erreur")
    b.close()
    assert_raises(() => b.new_tab(), "BrowserError")

testing.test("navigateur : onglets, navigation, cookies, stockage", t_browser)

failed := testing.run()
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) web.browser en échec")
print("web.browser : OK")
