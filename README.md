# GurobiPresolver.jl



## Overview

This is a MILP presolver for Gurobi.

Sometimes we want to solve a batch of very similar models derived from a base model. Gurobi has to perform `Presolve` on each of them, which is rather time consuming. The idea of this package is to apply a simple `preprocess`, and then let Gurobi do the rest with or without its own `Presolve`.

Note: It only works for MILP (Mixed Integer Linear Programming) without sos.

## Example

```{julia}
using GurobiPresolver

env = Gurobi.Env()
original_model = Gurobi.Model(env, "original")
read_model(original_model, "milp1.mps")

essential_variables = Set([1, 2, 3])
presolved_model, variable_mapping, constraint_mapping = preprocess(original_model, essential_variables)
```

- `presolved_model` is the presolved `Gurobi.Model`.

- `variable_mapping` is the many to one mapping of the variables from original model to the presolved model. If an original variable is missing from the `varible_mapping`, it means it is fixed and its values are already substituted into the constraints of `presolved_model`.

- `essential_variables` is a set of variables that we don't want the presolver to optimize away, so that later we may add constraints or change objective coefficients w.r.t. them.

## Benchmark

```
Read MPS format model from file milp1.mps
Reading time = 0.00 seconds
: 2076 rows, 2016 columns, 5580 nonzeros
Slowest time for minimize is 375 with 0.03900313377380371 sec.
Slowest time for maximize is 402 with 0.03914785385131836 sec.
Original model (#vars=2016, #constrs=2076) takes 22.054952383041382 sec.
Presolved model (#vars=860, #constrs=735) takes 9.916577100753784 sec with 275680 iterations.
```
