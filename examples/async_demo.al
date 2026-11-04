# async/await : tâches concurrentes, annulation, délai (docs/ASYNC.md)
use asyncio

async func fetch(name, delay):
    await asyncio.sleep(delay)
    print(f"{name} prêt")
    return name

async func main():
    # Trois tâches en vol en même temps : durée totale ~0.3 s, pas 0.6 s.
    results := await asyncio.gather([fetch("a", 0.3), fetch("b", 0.2), fetch("c", 0.1)])
    print(results)

    # Délai : la tâche trop lente est annulée.
    try:
        await asyncio.timeout(fetch("lente", 5), 0.1)
    catch e:
        print(f"abandon : {e.type}")

await main()
