module GurobiPresolver

export preprocess

using Gurobi
using MiniLogging
using Parameters

const LOGGER = get_logger(current_module())

include("IterSparseMatrix.jl")
using .IterSparseMatrix

include("Variables.jl")
using .Variables

include("Rules.jl")
using .Rules

include("Models.jl")
using .Models

include("VariableFixing.jl")
using .VariableFixing
include("SynonymSubstitution.jl")
using .SynonymSubstitution
include("VariableBounding.jl")
using .VariableBounding
include("ConstraintReduction.jl")
using .ConstraintReduction
include("CoefficientStrengthening.jl")
using .CoefficientStrengthening
include("ImpliedFreeVariableSubstitution.jl")
using .ImpliedFreeVariableSubstitution
include("ConstraintSimplification.jl")
using .ConstraintSimplification


include("simplify_substitutions.jl")

# Do not push!(redundant_constraints, row)
# Always use `remove_constraint(m, row, rhs_s, redundant_constraints)` instead.
# So that rows in redundant_constraints are zeroed in the model.



# function update_equivalence_classes(equivalence_classes::Dict{Int, Set{Int}}, a::Int, b::Int)
# 	if haskey(equivalence_classes, a)
# 		eq_class1 = equivalence_classes[a]
# 		if !haskey(equivalence_classes, b)
# 			equivalence_classes[b] = eq_class1
# 			push!(eq_class1, b)
# 		else
# 			eq_class2 = equivalence_classes[b]
# 			# Modify eq_class1 as union of eq_class1, eq_class2.
# 			union!(eq_class1, eq_class2)
# 			push!(eq_class1, b)
# 			# Redirect eq_class2 to eq_class1
# 			for x in eq_class2
# 				equivalence_classes[x] = eq_class1
# 			end
# 		end
# 	elseif haskey(equivalence_classes, b)
# 		update_equivalence_classes(equivalence_classes, b, a)
# 	else
# 		# Neither of them have equivalence_class.
# 		eq_class = Set([a, b])
# 		equivalence_classes[a] = eq_class
# 		equivalence_classes[b] = eq_class
# 	end
# end


const RULES = [
    :variable_fixing,
    :synonym_substitution,
    :variable_bounding, :constraint_reduction,
    :coefficient_strengthening,
    :implied_free_variable_substitution
]


function domain_propagate(
        model::DecomposedModel;
        rules::Vector{Symbol}=RULES,
        constraint_simplification::Bool=false,
        max_num_passes::Int=20
    )::ModelInfo
    m_info = ModelInfo()
    @debug(LOGGER, "Start initial bounds reductions for integers")
    map(tighten_lb, model.variables)
    map(tighten_ub, model.variables)

    updated = true
    pass = 0
    while updated && pass < max_num_passes
        pass += 1
        updated = false
        @info(LOGGER, "Pass $pass starts")

        for rule in rules
            stats = apply_rule(Val{rule}, model, m_info)
            updated = updated || has_updated(stats)
            @info(LOGGER, stats)
        end

        dropzeros!(model.m)
    end

    # Do it once is enough.
    if constraint_simplification
        stats = apply_rule(Val{:constraint_simplification}, model, m_info)
        @info(LOGGER, stats)
    end

    domain_propagate_check(model, m_info)
    simplify_substitutions(model, m_info)
    # Turn vtype to be binary if it seems one.
    # for x in variables
    #     if x.lb == 0 && x.ub == 1 && x.vtype == VTYPE_INTEGER
    #         x.vtype = VTYPE_BINARY
    #     end
    # end
    domain_propagate_check(model, m_info)
    log_effective_figures(model, m_info)
    m_info
end




function domain_propagate_check(model::DecomposedModel, m_info::ModelInfo)
    @unpack variables = model
    @unpack fixed, substitutions = m_info

    for col in fixed
        x = variables[col]
        if x.lb != x.ub
            error("$x in fixed yet lb != ub")
        end
    end

    for (k, expr) in substitutions
        if expr.coefs[k] != 0
            error("substitutions contains $k => $expr")
        end
    end
end

immutable Presolved
    model::Gurobi.Model
    variable_mapping
    constraint_mapping
    m_info::ModelInfo
    decomposed::DecomposedModel
end


function build_model(
        model::DecomposedModel, m_info::ModelInfo,
        essential_variables::Set{Int}
    )::Presolved

    env = Gurobi.Env()
    presolved_model = Gurobi.Model(env, "presolved")

    variables, variable_mapping = reduce_model_variables(
        m_info, model.variables, essential_variables
    )

    A, rhs_new, senses_new, constraint_mapping = reduce_model_constraints(
        length(variables), variable_mapping, model, m_info
    )

    lbs, ubs, vtypes = from_variables(variables)

    add_vars!(presolved_model, vtypes, zeros(length(variables)), lbs, ubs)
    update_model!(presolved_model)
    add_constrs!(presolved_model, A, senses_new, rhs_new)
    update_model!(presolved_model)

    Presolved(presolved_model, variable_mapping, constraint_mapping, m_info, model)
end


# """
# - Called by `reduce_model_variables` only.
# - We only care about variables that are fixed and essential.
# - We want to leave only 1 variable in the model,
# - so that additional constraints refering to these variables can be added later.
# - Return `to_remove => representative`.
# - `to_remove` > `representative`
# - All `to_remove` can be safely removed.
# """
# function get_fixed_essential_variable_redirection(
#         fixed_essential::Set{Int},
#         variables::Vector{Variable}
#     )
#     redirection = Dict{Int, Int}()
#     synonyms_by_value = Dict{Float64, Set{Int}}()
#     for x in fixed_essential
#         v = variables[x].lb
#         if haskey(synonyms_by_value, v)
#             push!(synonyms_by_value[v], x)
#         else
#             synonyms_by_value[v] = Set(x)
#         end
#     end

#     for xs in values(synonyms_by_value)
#         representative = minimum(xs)
#         for x in xs
#             if x != representative
#                 redirection[x] = representative
#             end
#         end
#     end
#     # length(synonyms_by_value) is num_representatives
#     # Which is also the extra number of variables that has to be kept due to essential_variables.
#     redirection, length(synonyms_by_value)
# end

"""
- Return `variables_new` which is the new model's variables.
- Return `variable_mapping`, which is `col_old => col_new`.
- Only values of `variable_map` are in the presolved model.
- Because we don't need them in the new model.
"""
function reduce_model_variables(
        m_info::ModelInfo,
        variables::Vector{Variable},
        essential_variables::Set{Int}
    )
    @unpack fixed, substitutions = m_info
    # # In best case, all variables in fixed can be removed, as constraints have no references to them.
    # removable_fixed = setdiff(fixed, essential_variables)
    # # Nothing in `fixed_essential`` is in removable_fixed.
    # fixed_essential = intersect(fixed, essential_variables)
    # redirection, num_extra_kept = get_fixed_essential_variable_redirection(fixed_essential, variables)
    # # All variables in the left one is fixed.
    # # All variables in the right one is not fixed.
    # # So there are no key conflictions.
    # merge!(redirection, synonyms)
    # # TODO TODO
    # num_to_remove = length(removable_fixed) + length(redirection) + length(substitutions)

    # Suppose essential_variables is empty for now.
    num_to_remove = length(fixed) + length(substitutions)

    # if num_extra_kept > 0
    #     @info(LOGGER, "Could have removed $(num_extra_kept) more variables if essential_variables were empty.")
    # end

    num_cols_new = length(variables) - num_to_remove
    variables_new = Array(Variable, num_cols_new)
    variable_mapping = Dict{Int, Int}()

    i = 0
    # `col` from small to big.
    for x in variables
        if x.id in fixed
            continue
        end

        if haskey(substitutions, x.id)
            continue
        end

        # if haskey(redirection, x.id)
        #     representative = redirection[x.id]
        #     # Since representative < x.id, it has already a mapping.
        #     if !haskey(substitutions, representative)
        #         variable_mapping[x.id] = variable_mapping[representative]
        #     else
        #         continue
        #     end
        #     continue
        # end

        i += 1
        variables_new[i] = x
        variable_mapping[x.id] = i
    end
    variables_new, variable_mapping
end


function reduce_model_constraints(
        num_cols_new,
        variable_mapping::Dict{Int, Int},
        model::DecomposedModel, m_info::ModelInfo
    )
    @unpack m, rhs_s, senses = model
    @unpack redundant_constraints = m_info
    # Note num_cols_new != length(variable_mapping)
    # num_cols_new == unique(values(variable_mapping))
    num_rows = size(m, 1)
    num_rows_new = num_rows - length(redundant_constraints)
    A = spzeros(num_rows_new, num_cols_new)

    rhs_new = Array(Float64, num_rows_new)
    senses_new = Array(Char, num_rows_new)

    constraint_mapping = Dict{Int, Int}()

    i = 0
    for row in 1:size(m, 1)
        if row in redundant_constraints
            continue
        end
        i += 1
        rhs_new[i] = rhs_s[row]
        senses_new[i] = senses[row]
        constraint_mapping[row] = i

        for (col, coef) in zip(findnz(m[row, :])...)
            A[i, variable_mapping[col]] = coef
        end
    end

    A, rhs_new, senses_new, constraint_mapping
end





function preprocess(grb_model::Gurobi.Model, essential_variables::Set{Int}=Set{Int}())
    model = DecomposedModel(grb_model)
    m_info = domain_propagate(model)

    build_model(model, m_info, essential_variables)
end


function test1()
    #model = Model(solver=Gurobi.GurobiSolver())
    #@variable(model, x1 >= 0)
    #@variable(model, 0 <= x2 <= 3.2, Int)
    #@variable(model, 1 <= x3 <= 5)
    #@variable(model, 2 <= x4 <= 4)
    #@variable(model, x5 >= -0.5, Int)

    #@constraint(model, 4 * x1 - 3 * x2 - 2 * x3 + x4 + 2 * x5 <= 13)
    #@constraint(model, -3 * x1 + 2 * x2 - x3 + 2 * x4 + 3 * x5 <= -9)

    #solve(model)
    #internal = internalmodel(model)
    #grb_model = MathProgBase.getrawsolver(internal)

    #preprocess(grb_model)
end


function test2()
    #model = Model(solver=Gurobi.GurobiSolver())
    #@variable(model, x[1:4])


    #@constraint(model, x[1] + x[2] + x[3] - 2 * x[4] <= -1)
    #@constraint(model, -x[1] - 3 * x[2] + 2 * x[3] - x[4] <= 4)
    #@constraint(model, -x[1] + x[2] + x[4] <= 0)
    #@constraint(model, 0 <= x[1])
    ##@constraint(model, 0 <= x[2])
    #@constraint(model, 1 <= x[3])
    #@constraint(model, 2 <= x[4])

    #@constraint(model, x[1] <= 2)
    #@constraint(model, x[2] <= 1)
    #@constraint(model, x[3] <= 2)
    #@constraint(model, x[4] <= 3)
end

#using Presolver
#Logging.configure(Presolver.LOGGER, level=DEBUG)

end