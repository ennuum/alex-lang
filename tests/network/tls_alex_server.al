# Serveur TLS écrit en Alex, lancé comme processus fils par tests/network/test_tls.al.
# usage : alex run tls_alex_server.al cert.pem key.pem
# Écrit son port, puis sert des connexions : « echo x » -> x en majuscules, « big n » -> n octets, « bye » -> ferme.
use network.tls as tls
use string as s
use os
use io
from core use to_int, len

args := os.args()
srv := tls.listen("127.0.0.1", 0, args[0], args[1], ["h2", "http/1.1"])
print(srv.port())
io.flush()
running := true
while running:
    conn := null
    try:
        conn = srv.accept()
    catch e:
        continue
    try:
        while true:
            line := conn.read_line(10.0)
            if line == null:
                break
            if s.starts_with(line, "echo "):
                conn.write_line(s.upper(s.substring(line, 5, len(line))))
            elif s.starts_with(line, "big "):
                conn.write_line(s.repeat("y", to_int(s.substring(line, 4, len(line)))))
            elif line == "info":
                conn.write_line(conn.socket.version + "|" + str(conn.socket.alpn))
            elif line == "stop":
                running = false
                break
            elif line == "bye":
                break
    catch e:
        io.flush()
    conn.close()
srv.close()
