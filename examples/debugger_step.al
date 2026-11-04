# Programme de validation manuel du débogueur Alex.
# Poser un point d'arrêt sur la ligne x := 6, puis tester Continuer et Pas à pas.
func double(n):
    result := n * 2
    return result

x := 3
x = double(x)
y := x + 4
print(x)
print(y)
