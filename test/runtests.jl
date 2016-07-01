using GurobiPresolver
using Base.Test

using Gurobi
using Logging
Logging.configure(GurobiPresolver.LOGGER, level=INFO)


include("test_milp1.jl")