// Pair gRPC de référence (bibliothèque standard de Go : net/http en HTTP/2 « h2c ») pour
// tests/network/test_grpc.al. Les messages protobuf (champ 1 : string, champ 2 : int32) sont codés à la main.
//
//	go run grpc_peer.go serve          serveur : écrit son port, sert jusqu'à /demo.Echo/Stop
//	go run grpc_peer.go client ADRESSE client : appelle le serveur Alex et écrit les résultats en JSON
package main

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"strings"
	"time"
)

func varint(v uint64) []byte {
	var b []byte
	for v >= 0x80 {
		b = append(b, byte(v)|0x80)
		v >>= 7
	}
	return append(b, byte(v))
}

func encodeRep(texte string, taille int) []byte {
	var m []byte
	m = append(m, 0x0a)
	m = append(m, varint(uint64(len(texte)))...)
	m = append(m, texte...)
	if taille != 0 {
		m = append(m, 0x10)
		m = append(m, varint(uint64(taille))...)
	}
	return m
}

// Premier champ string (numéro 1) d'un message.
func decodeTexte(m []byte) string {
	i := 0
	for i < len(m) {
		tag := m[i]
		i++
		switch tag & 7 {
		case 2:
			n, k := uvarint(m[i:])
			i += k
			if tag>>3 == 1 {
				return string(m[i : i+int(n)])
			}
			i += int(n)
		case 0:
			_, k := uvarint(m[i:])
			i += k
		default:
			return ""
		}
	}
	return ""
}

func uvarint(b []byte) (uint64, int) {
	v, n := binary.Uvarint(b)
	return v, n
}

func frame(m []byte) []byte {
	h := make([]byte, 5)
	binary.BigEndian.PutUint32(h[1:], uint32(len(m)))
	return append(h, m...)
}

func unframe(b []byte) [][]byte {
	var out [][]byte
	for len(b) >= 5 {
		n := binary.BigEndian.Uint32(b[1:5])
		out = append(out, b[5:5+n])
		b = b[5+n:]
	}
	return out
}

func serve() {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		panic(err)
	}
	srv := &http.Server{}
	srv.Protocols = new(http.Protocols)
	srv.Protocols.SetUnencryptedHTTP2(true)
	srv.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		msgs := unframe(body)
		w.Header().Set("Content-Type", "application/grpc")
		w.Header().Set("Trailer", "Grpc-Status, Grpc-Message, X-Fin")
		if v := r.Header.Get("X-Client"); v != "" {
			w.Header().Set("X-Vu", v)
		}
		switch r.URL.Path {
		case "/demo.Echo/Unary":
			t := decodeTexte(msgs[0])
			w.WriteHeader(200)
			w.Write(frame(encodeRep("écho : "+t, len(t))))
			w.Header().Set("Grpc-Status", "0")
			w.Header().Set("X-Fin", "oui")
		case "/demo.Echo/Stream":
			w.WriteHeader(200)
			for i := 1; i <= 3; i++ {
				w.Write(frame(encodeRep(fmt.Sprintf("n=%d", i), i)))
				w.(http.Flusher).Flush()
			}
			w.Header().Set("Grpc-Status", "0")
		case "/demo.Echo/Collect":
			var parts []string
			for _, m := range msgs {
				parts = append(parts, decodeTexte(m))
			}
			w.WriteHeader(200)
			w.Write(frame(encodeRep(strings.Join(parts, "+"), len(msgs))))
			w.Header().Set("Grpc-Status", "0")
		case "/demo.Echo/Big":
			w.WriteHeader(200)
			w.Write(frame(encodeRep(strings.Repeat("x", 300000), 300000)))
			w.Header().Set("Grpc-Status", "0")
		case "/demo.Echo/Fail":
			w.Header().Set("Grpc-Status", "5")
			w.Header().Set("Grpc-Message", "absent %C3%A9")
			w.WriteHeader(200)
		case "/demo.Echo/Stop":
			w.WriteHeader(200)
			w.Write(frame(encodeRep("arrêt", 0)))
			w.Header().Set("Grpc-Status", "0")
			go func() {
				time.Sleep(300 * time.Millisecond)
				os.Exit(0)
			}()
		default:
			w.Header().Set("Grpc-Status", "12")
			w.WriteHeader(200)
		}
	})
	fmt.Println(ln.Addr().(*net.TCPAddr).Port)
	srv.Serve(ln)
}

type result struct {
	Status  string
	Message string
	Texts   []string
	Header  string
}

func call(client *http.Client, base, path string, msgs [][]byte, md map[string]string) result {
	var body []byte
	for _, m := range msgs {
		body = append(body, frame(m)...)
	}
	req, _ := http.NewRequest("POST", base+path, bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/grpc")
	req.Header.Set("TE", "trailers")
	for k, v := range md {
		req.Header.Set(k, v)
	}
	resp, err := client.Do(req)
	if err != nil {
		return result{Status: "erreur " + err.Error()}
	}
	data, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	st := resp.Trailer.Get("Grpc-Status")
	msg := resp.Trailer.Get("Grpc-Message")
	if st == "" {
		st = resp.Header.Get("Grpc-Status")
		msg = resp.Header.Get("Grpc-Message")
	}
	var texts []string
	for _, m := range unframe(data) {
		texts = append(texts, decodeTexte(m))
	}
	return result{Status: st, Message: msg, Texts: texts, Header: resp.Header.Get("X-Vu")}
}

func client(addr string) {
	tr := &http.Transport{}
	tr.Protocols = new(http.Protocols)
	tr.Protocols.SetUnencryptedHTTP2(true)
	c := &http.Client{Transport: tr}
	base := "http://" + addr
	out := map[string]result{}
	out["unary"] = call(c, base, "/demo.Echo/Unary", [][]byte{encodeRep("Go", 0)}, map[string]string{"X-Client": "go"})
	out["stream"] = call(c, base, "/demo.Echo/Stream", [][]byte{encodeRep("trois", 0)}, nil)
	out["collect"] = call(c, base, "/demo.Echo/Collect", [][]byte{encodeRep("a", 0), encodeRep("b", 0), encodeRep("c", 0)}, nil)
	out["big"] = call(c, base, "/demo.Echo/Unary", [][]byte{encodeRep(strings.Repeat("y", 200000), 0)}, nil)
	out["fail"] = call(c, base, "/demo.Echo/Fail", [][]byte{encodeRep("x", 0)}, nil)
	out["unknown"] = call(c, base, "/demo.Echo/Absente", [][]byte{encodeRep("x", 0)}, nil)
	out["stop"] = call(c, base, "/demo.Echo/Stop", [][]byte{encodeRep("x", 0)}, nil)
	if len(out["big"].Texts) == 1 {
		out["big"] = result{Status: out["big"].Status, Texts: []string{fmt.Sprint(len(out["big"].Texts[0]))}}
	}
	j, _ := json.Marshal(out)
	fmt.Println(string(j))
}

func main() {
	if len(os.Args) > 1 && os.Args[1] == "serve" {
		serve()
	} else {
		client(os.Args[2])
	}
}
