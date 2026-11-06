# ALEX STANDARD LIBRARY — web.server.server_metrics
#
# Mesures du serveur : connexions (ouvertes, actives, refusées, expirées), requêtes par méthode et par classe de
# statut, octets reçus / envoyés, durées de traitement (min, max, moyenne, histogramme, quantiles approchés),
# erreurs. Exportables en dict (JSON) ou au format texte de Prometheus.
#
#   use web.server.server_metrics as sm
#   m := sm.Metrics()
#   m.request_done("GET", 200, 0.012, 120, 3400)
#   m.snapshot()["requests"]          # 1
#   m.quantile(0.95)                  # durée sous laquelle tombent 95 % des requêtes (borne d'histogramme)
#   print(m.to_prometheus("alex_http"))
#
# Utilisé automatiquement par web.server.Server (server.metrics) ; route de diagnostic : voir server.al.

from core use len, type, to_float
from collections use append, keys
use string as _s
use time as _time

# Bornes de l'histogramme des durées (secondes).
const BUCKETS := [0.001, 0.0025, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0]

class Metrics:
    func init():
        self.started_at = _time.time()
        self.reset()

    func reset():
        self.connections_opened = 0
        self.connections_closed = 0
        self.connections_rejected = 0
        self.connections_timed_out = 0
        self.tls_handshake_failures = 0
        self.requests = 0
        self.by_method = {}
        self.by_status_class = {"1xx": 0, "2xx": 0, "3xx": 0, "4xx": 0, "5xx": 0}
        self.by_status = {}
        self.bytes_in = 0
        self.bytes_out = 0
        self.handler_errors = 0
        self.protocol_errors = 0
        self.async_cancelled = 0         # gestionnaires async annulés (client parti pendant l'attente)
        self.websockets_opened = 0       # sessions WebSocket ouvertes (poignées de main réussies)
        self.streams_opened = 0          # réponses en flux commencées (web.server.streaming)
        self.duration_sum = 0.0
        self.duration_min = null
        self.duration_max = 0.0
        self.histogram = []
        for b in BUCKETS:
            append(self.histogram, 0)
        self.overflow = 0

    func connection_opened():
        self.connections_opened += 1

    func connection_closed():
        self.connections_closed += 1

    func connection_rejected():
        self.connections_rejected += 1

    func connection_timed_out():
        self.connections_timed_out += 1

    func active_connections():
        return self.connections_opened - self.connections_closed

    func protocol_error():
        self.protocol_errors += 1

    func handler_error():
        self.handler_errors += 1

    # Requête terminée : méthode, statut, durée (s), octets reçus, octets envoyés.
    func request_done(method, status, duration, bytes_in=0, bytes_out=0):
        self.requests += 1
        self.by_method[method] = (self.by_method[method] if method in self.by_method else 0) + 1
        cls := str(status // 100) + "xx"
        if cls in self.by_status_class:
            self.by_status_class[cls] = self.by_status_class[cls] + 1
        self.by_status[status] = (self.by_status[status] if status in self.by_status else 0) + 1
        self.bytes_in += bytes_in
        self.bytes_out += bytes_out
        d := to_float(duration)
        self.duration_sum += d
        if self.duration_min == null or d < self.duration_min:
            self.duration_min = d
        if d > self.duration_max:
            self.duration_max = d
        i := 0
        placed := false
        while i < len(BUCKETS):
            if d <= BUCKETS[i]:
                self.histogram[i] = self.histogram[i] + 1
                placed = true
                break
            i += 1
        if not placed:
            self.overflow += 1

    func mean_duration():
        if self.requests == 0:
            return 0.0
        return self.duration_sum / self.requests

    # Quantile approché (borne supérieure de l'intervalle d'histogramme qui l'atteint).
    func quantile(q):
        if self.requests == 0:
            return 0.0
        target := q * self.requests
        acc := 0
        i := 0
        while i < len(BUCKETS):
            acc += self.histogram[i]
            if acc >= target:
                return BUCKETS[i]
            i += 1
        return self.duration_max

    func uptime():
        return _time.time() - self.started_at

    func snapshot():
        return {"uptime": self.uptime(), "connections": {"opened": self.connections_opened, "closed": self.connections_closed, "active": self.active_connections(), "rejected": self.connections_rejected, "timed_out": self.connections_timed_out, "tls_failures": self.tls_handshake_failures}, "requests": self.requests, "by_method": self.by_method, "by_status_class": self.by_status_class, "bytes_in": self.bytes_in, "bytes_out": self.bytes_out, "errors": {"handler": self.handler_errors, "protocol": self.protocol_errors}, "async_cancelled": self.async_cancelled, "websockets_opened": self.websockets_opened, "streams_opened": self.streams_opened, "duration": {"mean": self.mean_duration(), "min": self.duration_min if self.duration_min != null else 0.0, "max": self.duration_max, "p50": self.quantile(0.5), "p95": self.quantile(0.95), "p99": self.quantile(0.99)}}

    # Format d'exposition texte de Prometheus.
    func to_prometheus(prefix="alex_http"):
        lines := []
        append(lines, "# TYPE " + prefix + "_requests_total counter")
        for m in keys(self.by_method):
            append(lines, prefix + "_requests_total{method=\"" + m + "\"} " + str(self.by_method[m]))
        append(lines, "# TYPE " + prefix + "_responses_total counter")
        for c in keys(self.by_status_class):
            append(lines, prefix + "_responses_total{class=\"" + c + "\"} " + str(self.by_status_class[c]))
        append(lines, "# TYPE " + prefix + "_connections_active gauge")
        append(lines, prefix + "_connections_active " + str(self.active_connections()))
        append(lines, "# TYPE " + prefix + "_connections_total counter")
        append(lines, prefix + "_connections_total " + str(self.connections_opened))
        append(lines, "# TYPE " + prefix + "_bytes_received_total counter")
        append(lines, prefix + "_bytes_received_total " + str(self.bytes_in))
        append(lines, "# TYPE " + prefix + "_bytes_sent_total counter")
        append(lines, prefix + "_bytes_sent_total " + str(self.bytes_out))
        append(lines, "# TYPE " + prefix + "_errors_total counter")
        append(lines, prefix + "_errors_total{kind=\"handler\"} " + str(self.handler_errors))
        append(lines, prefix + "_errors_total{kind=\"protocol\"} " + str(self.protocol_errors))
        append(lines, "# TYPE " + prefix + "_async_cancelled_total counter")
        append(lines, prefix + "_async_cancelled_total " + str(self.async_cancelled))
        append(lines, "# TYPE " + prefix + "_request_duration_seconds histogram")
        acc := 0
        i := 0
        while i < len(BUCKETS):
            acc += self.histogram[i]
            append(lines, prefix + "_request_duration_seconds_bucket{le=\"" + str(BUCKETS[i]) + "\"} " + str(acc))
            i += 1
        append(lines, prefix + "_request_duration_seconds_bucket{le=\"+Inf\"} " + str(self.requests))
        append(lines, prefix + "_request_duration_seconds_sum " + str(self.duration_sum))
        append(lines, prefix + "_request_duration_seconds_count " + str(self.requests))
        append(lines, "# TYPE " + prefix + "_uptime_seconds gauge")
        append(lines, prefix + "_uptime_seconds " + str(self.uptime()))
        return _s.join("\n", lines) + "\n"

func metrics():
    return Metrics()
