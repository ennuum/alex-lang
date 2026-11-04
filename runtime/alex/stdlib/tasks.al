
# Lance f dans une nouvelle tâche (exécutée au prochain yield_now) ; renvoie son identifiant.
func spawn(f: func()) -> int:
    return __rt_spawn(__addr(f))

# Passe la main à la tâche prête suivante.
func yield_now():
    __rt_yield()

# Attend la fin de toutes les autres tâches.
func run():
    while __rt_tasks_alive() > 1:
        __rt_yield()

func current() -> int:
    return __rt_task_id()

func alive() -> int:
    return __rt_tasks_alive()
