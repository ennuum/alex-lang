# Programme fils des tests de tests/sysapp (lancé par ./alex run).
use ipc.shared_memory as shm
use ipc.message_queue as mq
use ipc.channel as ch
use os
args := os.args()
kind := args[0]
if kind == "count":
    m := shm.SharedMemory(args[1], 4096)
    c := shm.SharedCounter(m, 8)
    lk := shm.SharedMutex(m, 0)
    i := 0
    while i < 200:
        lk.lock()
        v := m.get(16, "i64")
        m.set(16, "i64", v + 1)
        lk.unlock()
        c.add(1)
        i += 1
    m.close()
elif kind == "mq":
    q := mq.open(args[1], 8, 256, args[2])
    q.send("salut du fils")
    q.send_json({"n": 42})
    q.close()
elif kind == "client":
    c := ch.connect(args[1], 3)
    print(c.call("somme", [2, 3]))
    try:
        c.call("boom", null)
    catch RemoteError as e:
        print("remote", e.message)
    c.close()
