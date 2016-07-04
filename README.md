# GurobiPresolver.jl



## Overview

This is a MILP presolver for Gurobi.

Sometimes we want to solve a batch of very similar models derived from a base model. Gurobi has to perform `Presolve` on each of them, which is rather time consuming. The idea of this package is to apply a simple `preprocess` on the base model, and then solve the smaller derived models with or without Gurobi's `Presolve`.

Note: It only works for MILP (Mixed Integer Linear Programming) without sos.

## Techniques Applied

- Variable Bounding
- Variable Fixing
- Constraint Bounding
- Synonym Substitution

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

- `variable_mapping` is the many to one mapping of the variables from original model to the presolved model. If an original variable is missing from it, we can tell it is fixed and its values are already substituted into the constraints of `presolved_model`.

- `essential_variables` is a set of variables that we don't want the presolver to optimize away, so that later we may add constraints or change objective coefficients w.r.t. them.

## Benchmark

```
Read MPS format model from file milp1.mps
Reading time = 0.00 seconds
: 2076 rows, 2016 columns, 5580 nonzeros
Slowest time for minimize is 375 with 0.040085792541503906 sec.
Slowest time for maximize is 365 with 0.04070901870727539 sec.
Original model (#vars=2016, #constrs=2076) takes 22.091896772384644 sec.
Gurobi presolved model (#vars=222, #constrs=308).
Presolved model (#vars=860, #constrs=735) takes 9.94690752029419 sec with 275680 iterations.
```
