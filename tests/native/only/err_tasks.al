# Exception non rattrapée dans une tâche : trace et code de sortie 1, comme une erreur du programme.
use tasks
func fail_later(n: int):
    tasks.yield_now()
    print(10 // n)
tasks.spawn(() => fail_later(2))
tasks.spawn(() => fail_later(0))
tasks.run()
print("jamais")
