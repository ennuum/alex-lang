# ALEX STANDARD LIBRARY — web.client.retry_policy
#
# Politique de reprise du client : quelles requêtes rejouer, après quelles erreurs ou quels statuts, et après
# combien de temps (attente exponentielle plafonnée, Retry-After respecté).
#
# Par défaut : 2 reprises, uniquement pour les méthodes idempotentes (GET, HEAD, PUT, DELETE, OPTIONS, TRACE),
# après une erreur réseau ou un délai dépassé, ou un statut 429, 502, 503, 504. Attentes : 0,5 s, 1 s, 2 s…
# plafonnées à 30 s ; un Retry-After du serveur (secondes ou date) est suivi s'il ne dépasse pas max_backoff.
#
#   use web.client.retry_policy as rp
#   p := rp.RetryPolicy(3, 0.2)
#   p.delay(2)                         # 0.4 (0.2 × 2^(2-1))
#   p.should_retry_status("GET", 503, 0)    # true
#   p.should_retry_status("POST", 503, 0)   # false (non idempotente)
#   rp.never()                         # aucune reprise
#   rp.RetryPolicy(3, 0.5, 30, [429, 503], ["GET", "POST"])   # POST aussi (si l'API est idempotente côté serveur)
#
# Erreurs : ClientError (paramètre invalide).

from core use len, type, to_float
use web.client.client_errors as _err
use web.http.method as _method
use web.http.date_header as _date

const DEFAULT_STATUSES := [429, 502, 503, 504]

class RetryPolicy:
    func init(max_retries=2, backoff_factor=0.5, max_backoff=30.0, statuses=null, methods=null, retry_on_errors=true, respect_retry_after=true):
        if type(max_retries) != "int" or max_retries < 0:
            _err.client_error("RetryPolicy", "max_retries entier >= 0 attendu")
        self.max_retries = max_retries
        self.backoff_factor = backoff_factor
        self.max_backoff = max_backoff
        self.statuses = statuses if statuses != null else DEFAULT_STATUSES
        self.methods = methods if methods != null else _method.IDEMPOTENT
        self.retry_on_errors = retry_on_errors
        self.respect_retry_after = respect_retry_after

    func allows_method(method):
        return method in self.methods

    # Rejouer après une erreur (attempt : reprises déjà faites) ?
    func should_retry_error(method, e, attempt):
        if attempt >= self.max_retries or not self.retry_on_errors:
            return false
        if not self.allows_method(method):
            return false
        return _err.is_retryable(e)

    # Rejouer après une réponse de ce statut ?
    func should_retry_status(method, status, attempt):
        if attempt >= self.max_retries:
            return false
        return status in self.statuses and self.allows_method(method)

    # Attente avant la reprise n° attempt (1, 2, ...) ; response : réponse reçue (Retry-After), ou null.
    func delay(attempt, response=null):
        if self.respect_retry_after and response != null:
            ra := _date.retry_after_seconds(response.headers.get("retry-after"))
            if ra != null and ra <= self.max_backoff:
                return to_float(ra)
        d := self.backoff_factor
        k := 1
        while k < attempt:
            d = d * 2
            k += 1
        if d > self.max_backoff:
            d = self.max_backoff
        return to_float(d)

    func copy():
        return RetryPolicy(self.max_retries, self.backoff_factor, self.max_backoff, self.statuses, self.methods, self.retry_on_errors, self.respect_retry_after)

func default():
    return RetryPolicy()

func never():
    return RetryPolicy(0)

# Depuis un entier (nombre de reprises), une RetryPolicy, false (aucune) ou null (défaut).
func from_value(value):
    if value == null:
        return RetryPolicy()
    if value == false:
        return never()
    if isinstance(value, RetryPolicy):
        return value
    if type(value) == "int":
        return RetryPolicy(value)
    _err.client_error("retry_policy.from_value", "entier, RetryPolicy, false ou null attendu")
