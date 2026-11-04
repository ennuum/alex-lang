# async / await, compréhensions de dict imbriquées, with.

async func compute(n):
    return n * n

async func main():
    vals := []
    for i in 1..4:
        vals.append(await compute(i))
    return vals

print(await main())
grid := {f"{i},{j}": i * j for i in 0..3 for j in 0..3 if i != j}
print(grid)
print(sorted(grid.keys())[0:3])
s := {1, 2, 3}
print(len(s))
