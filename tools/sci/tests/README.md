# Générateurs de tests de la bibliothèque scientifique (Phase 2)

`tests/test_<module>.al` (array, linalg, stats, numeric, calculus, science2_integration) sont **générés** :
les valeurs attendues viennent de NumPy / SciPy / SymPy (références indépendantes), jamais des modules testés.

    pip install numpy scipy sympy
    python3 tools/sci/tests/gen_test_array.py        # réécrit tests/test_array.al
    make test-sci2                                   # lance les six suites

`harness.py` fournit la classe `Suite` (groupes, `close`, `arr`, `eq`, `err`, `define`...) et l'en-tête commun des tests.
Ne pas éditer les `tests/test_*.al` générés à la main : modifier le générateur puis régénérer.
