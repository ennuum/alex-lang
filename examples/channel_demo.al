# Canaux : tube producteur -> travailleurs -> collecteur, select avec délai (docs/CHANNELS.md)
use asyncio
use channel
from channel use Channel

async func produire(jobs, n):
    for i in 1..(n + 1):
        await jobs.send(i)          # tampon plein -> le producteur attend (contre-pression)
    jobs.close()                    # les travailleurs s'arrêtent quand le canal est vidé

async func travailler(id, jobs, resultats):
    async func traiter(job):
        await asyncio.sleep(0.01 * job)
        await resultats.send((id, job, job * job))
    await channel.each(jobs, traiter)

async func main():
    jobs := Channel(2)
    resultats := Channel()
    produire(jobs, 6)
    travailleurs := [travailler(i, jobs, resultats) for i in 0..3]
    collecte := channel.drain(resultats)
    await asyncio.gather(travailleurs)
    resultats.close()
    for r in await collecte:
        print(f"travailleur {r[0]} : {r[1]}² = {r[2]}")

    # select : le premier événement gagne ; un délai borne l'attente
    alerte := Channel()
    donnees := Channel(1)
    try:
        await asyncio.timeout(channel.select([alerte, donnees]), 0.02)
    catch e:
        print(f"rien reçu : {e.type}")
    donnees.try_send("bonjour")
    r := await channel.select([alerte, donnees])
    print(f"cas {r[0]} -> {r[2]}")

await main()
