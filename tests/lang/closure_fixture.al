func make_counter(start):
    n := start
    func tick():
        n = n + 1
        return n
    return tick

func scaler(k):
    return x => x * k

func twice(f):
    return x => f(f(x))
