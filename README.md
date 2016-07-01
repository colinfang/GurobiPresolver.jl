# GurobiPresolver.jl



## Overview

This is a presolver for Gurobi.

## Example

```{julia}

```

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
