# GurobiPresolver.jl

## Overview

This is a MILP presolver for Gurobi.

Sometimes we want to solve a batch of very similar models derived from a base model. Gurobi has to perform `Presolve` on each of them, which is rather time consuming. The idea of this package is to apply a simple `preprocess` on the base model, and then solve the smaller derived models with or without Gurobi's `Presolve`.

Note: It only works for MILP (Mixed Integer Linear Programming) without sos.

## Techniques

- Variable Bounding - Tighten a variable bounds using other variables bounds as well as rhs values.
    - Ref 3.2
- Variable Fixing - If a variable has the same lower & upper bounds, its corresponding constraints can be simplified.
- Constraint Bounding - Remove constraints if rhs are not helpful.
    - Ref 3.1
- Synonym Substitution - If the constraint looks like `a * x - a * y = 0`, `x` & `y` are synonyms. Their constraints and bounds can be merged.
- Coefficient Strengthening - ...
    - Ref 3.3

## Example

```{julia}
using GurobiPresolver

env = Gurobi.Env()
original_model = Gurobi.Model(env, "original")
read_model(original_model, "milp1.mps")

essential_variables = Set([1, 2, 3])
presolved_model, variable_mapping, constraint_mapping, variables = preprocess(original_model, essential_variables)
```

- `presolved_model` - The presolved `Gurobi.Model`.

- `variable_mapping` - The many to one mapping of the variables from original model to the presolved model. If an original variable is missing from it, the variable is fixed and its value is already substituted into the constraints of `presolved_model`.

- `essential_variables` - A set of variables that we don't want the presolver to optimize away, so that later we may add constraints or change objective coefficients w.r.t. them.

- `variables` - A list of tightened variables of the original model.

## Benchmark

`apply_synonym_substitution = false`

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

`apply_synonym_substitution = true`

```
Read MPS format model from file milp1.mps
Reading time = 0.00 seconds
: 2076 rows, 2016 columns, 5580 nonzeros
preprocess starts
  0.095954 seconds (1.13 M allocations: 37.987 MB, 4.38% gc time)
preprocess ends
Slowest time for minimize is 372 with 0.02973198890686035 sec.
Slowest time for maximize is 374 with 0.04725503921508789 sec.
There are 33 more variables fixed that we fail to detect.
test_variable_fixing starts
 29.118530 seconds (2.46 k allocations: 225.641 KB)
test_variable_fixing ends
test_synonym_substitution starts
  2.589812 seconds (9.79 k allocations: 843.734 KB)
test_synonym_substitution ends
Original model (#vars=2016, #constrs=2076) takes 22.563799142837524 sec to find min & max of 764 variables.
Gurobi presolved model (#vars=222, #constrs=308).
Presolved model (#vars=764, #constrs=639) takes 13.976390838623047 sec with 353779 iterations to find min & max of 764 variables.
```