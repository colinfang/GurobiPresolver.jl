module GurobiPresolver

export preprocess

using Gurobi
using Logging

const LOGGER = Logger("$(current_module())")

include("Stats.jl")
using .Stats

include("IterSparseMatrix.jl")
using .IterSparseMatrix

include("variable.jl")

include("variable_fixing.jl")
include("synonym_substitution.jl")
include("variable_bounding.jl")
include("constraint_bounding.jl")
include("constraint_simplification.jl")


function update_equivalence_classes(equivalence_classes::Dict{Int, Set{Int}}, a::Int, b::Int)
	if haskey(equivalence_classes, a)
		eq_class1 = equivalence_classes[a]
		if !haskey(equivalence_classes, b)
			equivalence_classes[b] = eq_class1
			push!(eq_class1, b)
		else
			eq_class2 = equivalence_classes[b]
			# Modify eq_class1 as union of eq_class1, eq_class2.
			union!(eq_class1, eq_class2)
			push!(eq_class1, b)
			# Redirect eq_class2 to eq_class1
			for x in eq_class2
				equivalence_classes[x] = eq_class1
			end
		end
	elseif haskey(equivalence_classes, b)
		update_equivalence_classes(equivalence_classes, b, a)
	else
		# Neither of them have equivalence_class.
		eq_class = Set([a, b])
		equivalence_classes[a] = eq_class
		equivalence_classes[b] = eq_class
	end
end




"""
- Called by `domain_propagate` only.
- Move synonyms class that are fixed to `fixed` & update their bounds.
- Redirect `x => y`, `y = z`, `a => y` to `a = z`, `y => z`, `x => z`
- Return `(to_remove => representative)`
- `to_remove` > `representative`
- All `to_remove` can be safely removed.
"""
function redirect_synonyms(
        variables::Vector{Variable},
        synonyms::Dict{Int, Int}, fixed::Set{Int},
    )
    num_synonyms_pair = length(synonyms)
    num_fixed = length(fixed)

    synonym_classes = Dict{Int, Set{Int}}()

    for (a, b) in synonyms
        update_equivalence_classes(synonym_classes, a, b)
    end

    redirection = Dict{Int, Int}()

    for eq_class in values(synonym_classes)
        fixed_lot = intersect(eq_class, fixed)
        if !isempty(fixed_lot)
            # As long as there is one fixed, all eq_class are fixed.
            the_fixed_one = variables[first(fixed_lot)]

            for x in eq_class
                if !(x in fixed)
                    # Update bounds.
                    variables[x].lb = the_fixed_one.lb
                    variables[x].ub = the_fixed_one.ub
                    push!(fixed, x)
                end
            end
        else
            representative = minimum(eq_class)
            for x in eq_class
                if x != representative
                    redirection[x] = representative
                end
            end
        end
    end

    info(LOGGER, "redirect_synonyms #fixed $(num_fixed) => $(length(fixed)), #synonyms $(num_synonyms_pair) => $(length(redirection))")
    redirection
end


function domain_propagate(
        m, senses::Vector{Char}, rhs_s::Vector{Float64},
        variables::Vector{Variable};
        variable_fixing::Bool=true,
        synonym_substitution::Bool=false,
        variable_bounding::Bool=true,
        constraint_bounding::Bool=true,
        constraint_simplification::Bool=false,
        max_num_passes::Int=20
    )
    fixed = Set{Int}()
    redundant_constraints = Set{Int}()
    synonyms = Dict{Int, Int}()

    debug(LOGGER, "Start initial bounds reductions for integers.")

    map(tighten_bounds, variables)

    updated = true
    pass = 0
    while updated && pass < max_num_passes
        pass += 1
        info(LOGGER, "Pass $pass starts.")

        variable_fixing_stats = variable_bounding ?
            apply_variable_fixing(m, fixed, variables, rhs_s) :
            VariableFixingStats(0, 0)
        synonym_substitution_stats = synonym_substitution ?
            apply_synonym_substitution(m, senses, rhs_s, variables, redundant_constraints, synonyms) :
            SynonymSubstitutionStats(0)
        variable_bounding_stats = variable_bounding ?
            apply_variable_bounding(m, senses, rhs_s, variables, redundant_constraints) :
            VariableBoundingStats(0, 0)
        constraint_bounding_stats = constraint_bounding ?
            apply_constraint_bounding(m, senses, rhs_s, variables, redundant_constraints) :
            ConstraintBoundingStats(0)
        # TODO?
        # Do not consider synonyms, as they can be fixed.
        num_effective_variables = size(m, 2) - length(fixed)
        num_effective_constraints = size(m, 1) - length(redundant_constraints)

        pass_stats = PassStats(
            variable_fixing_stats, synonym_substitution_stats,
            variable_bounding_stats, constraint_bounding_stats,
            num_effective_variables, num_effective_constraints
        )

        updated = has_updated(variable_fixing_stats) ||
            has_updated(synonym_substitution_stats) ||
            has_updated(variable_bounding_stats) ||
            has_updated(constraint_bounding_stats)

        dropzeros!(m)
        info(LOGGER, "Pass $pass $(pass_stats).")
    end

    # Do it once is enough.
    constraint_simplification_stats = constraint_simplification ?
        apply_constraint_simplification(m, senses, rhs_s, variables, redundant_constraints) :
        ConstraintSimplificationStats(0)
    info(LOGGER, "$(constraint_simplification_stats).")
    # Make a better `synonym`.
    synonyms = redirect_synonyms(variables, synonyms, fixed)
    fixed, redundant_constraints, synonyms
end

function post_domain_propagate_check(
        variables::Vector{Variable},
        rhs_s::Vector{Float64},
        synonyms::Dict{Int, Int},
        fixed::Set{Int},
        redundant_constraints::Set{Int}
    )

    for col in fixed
        x = variables[col]
        if x.lb != x.ub
            error("$x in fixed yet lb != ub")
        end
    end

    num_fixed = length(fixed)
    num_synonyms_pair = length(synonyms)
    num_redundant_constraints = length(redundant_constraints)

    num_effective_variables = length(variables) - num_fixed - num_synonyms_pair
    num_effective_constraints = length(rhs_s) - num_redundant_constraints

    info(LOGGER, "Finally #fixed=$(num_fixed), #redundant_constraints=$(num_redundant_constraints), #synonyms=$(num_synonyms_pair).")
    info(LOGGER, "Finally #effected_variables=$(num_effective_variables), #effective_constraints=$(num_effective_constraints).")
end


function build_model(
        m, variables::Vector{Variable},
        senses::Vector{Char}, rhs_s::Vector{Float64},
        fixed::Set{Int}, redundant_constraints::Set{Int},
        synonyms::Dict{Int, Int},
        essential_variables::Set{Int}
    )
    env = Gurobi.Env()
    model = Gurobi.Model(env, "presolved")

    variables_new, variable_mapping = reduce_model_variables(
        fixed, synonyms, variables, essential_variables
    )

    A, rhs_new, senses_new, constraint_mapping = reduce_model_constraints(
        length(variables_new), variable_mapping, m, redundant_constraints, rhs_s, senses
    )

    lbs, ubs, vtypes = from_variables(variables_new)

    add_vars!(model, vtypes, zeros(length(variables_new)), lbs, ubs)
    update_model!(model)
    add_constrs!(model, A, senses_new, rhs_new)
    update_model!(model)
    model, variable_mapping, constraint_mapping
end


"""
- Called by `reduce_model_variables` only.
- We only care about variables that are fixed and essential.
- We want to leave only 1 variable in the model,
- so that additional constraints refering to these variables can be added later.
- Return `to_remove => representative`.
- `to_remove` > `representative`
- All `to_remove` can be safely removed.
"""
function get_fixed_essential_variable_redirection(
        fixed_essential::Set{Int},
        variables::Vector{Variable}
    )
    redirection = Dict{Int, Int}()
    synonyms_by_value = Dict{Float64, Set{Int}}()
    for x in fixed_essential
        v = variables[x].lb
        if haskey(synonyms_by_value, v)
            push!(synonyms_by_value[v], x)
        else
            synonyms_by_value[v] = Set(x)
        end
    end

    for xs in values(synonyms_by_value)
        representative = minimum(xs)
        for x in xs
            if x != representative
                redirection[x] = representative
            end
        end
    end
    # length(synonyms_by_value) is num_representatives
    # Which is also the extra number of variables that has to be kept due to essential_variables.
    redirection, length(synonyms_by_value)
end

"""
- Return `variables_new`.
- Return `variable_mapping`, which is `col_old => col_new`.
- Variables that are not in `variable_map` are fixed & removed.
"""
function reduce_model_variables(
        fixed::Set{Int}, synonyms::Dict{Int, Int},
        variables::Vector{Variable},
        essential_variables::Set{Int}
    )
    # In best case, all variables in fixed can be removed, as constraints have no references to them.
    removable_fixed = setdiff(fixed, essential_variables)
    # Nothing in `fixed_essential`` is in removable_fixed.
    fixed_essential = intersect(fixed, essential_variables)
    redirection, num_extra_kept = get_fixed_essential_variable_redirection(fixed_essential, variables)
    # All variables in the left one is fixed.
    # All variables in the right one is not fixed.
    # So there are no key conflictions.
    merge!(redirection, synonyms)

    num_to_remove = length(removable_fixed) + length(redirection)

    if num_extra_kept > 0
        info(LOGGER, "Could have removed $(num_extra_kept) more variables if essential_variables were empty.")
    end

    num_cols_new = length(variables) - num_to_remove
    variables_new = Array(Variable, num_cols_new)
    variable_mapping = Dict{Int, Int}()

    i = 0
    # `col` from small to big.
    for x in variables
        if x.id in removable_fixed
            continue
        end
        if haskey(redirection, x.id)
            representative = redirection[x.id]
            # Since representative < x.id, it has already a mapping.
            variable_mapping[x.id] = variable_mapping[representative]
            continue
        end
        i += 1
        variables_new[i] = x
        variable_mapping[x.id] = i
    end
    variables_new, variable_mapping
end


function reduce_model_constraints(
        num_cols_new,
        variable_mapping::Dict{Int, Int}, m,
        redundant_constraints::Set{Int},
        rhs_s::Vector{Float64}, senses::Vector{Char}
    )
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


function preprocess(model::Gurobi.Model, essential_variables::Set{Int}=Set{Int}())
    if is_qp(model) || is_qcp(model)
        error("Only works with MILP!")
    end

    rhs_s = Gurobi.get_dblattrarray(model, "RHS", 1, num_constrs(model))
    senses = Gurobi.get_charattrarray(model, "Sense", 1, num_constrs(model))

    variables = get_variables(model)

    m = get_constrmatrix(model)

    fixed, redundant_constraints, synonyms = domain_propagate(m, senses, rhs_s, variables)

    post_domain_propagate_check(
        variables, rhs_s, synonyms, fixed, redundant_constraints
    )

    presolved_model, variable_mapping, constraint_mapping = build_model(
        m, variables, senses, rhs_s,
        fixed, redundant_constraints, synonyms, essential_variables
    )
    presolved_model, variable_mapping, constraint_mapping, variables
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