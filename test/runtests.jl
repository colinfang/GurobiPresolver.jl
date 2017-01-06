using GurobiPresolver
using Base.Test

using Gurobi

using GurobiPresolver: Variable, apply_rule, DecomposedModel, ModelInfo
using GurobiPresolver: print_constraints
using Parameters

include("utils.jl")
include("test_model.jl")

function print_presolved_model(model::Gurobi.Model)
    presolved = @time_fun preprocess(model)

    x = get_model_info(model)
    println("Original Model: $x")

    x = get_model_info(presolved.model)
    println("My Presolver: $x")

    setparams!(model, LogToConsole=0)

    x = get_model_info(Gurobi.presolve_model(model))
    println("Default Gurobi Presolve: $x")

    setparams!(model, DualReductions=0)
    x = get_model_info(Gurobi.presolve_model(model))
    println("Gurobi Presolve w/o DualReductions: $x")
end


include("test_milp1.jl")
# include("test_variable_fixing.jl")
# include("test_synonym_substitution.jl")
# include("test_variable_bounding.jl")
