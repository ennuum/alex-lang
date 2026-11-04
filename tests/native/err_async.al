# Exception non rattrapée dans une tâche, relancée par await dans le programme principal : même trace que la VM.
use asyncio
async func compute(n: int) -> int:
    await asyncio.sleep(0)
    return 10 // n
async func relay(n: int) -> int:
    return await compute(n) + 1
print(await relay(5))
print(await relay(0))
