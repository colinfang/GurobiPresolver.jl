module GurobiPresolver

export preprocess

using Gurobi
using Logging

const LOGGER = Logger("$(current_module())")

include("Stats.jl")
using .Stats

include("variable_fixing.jl")
include("synonym_substitution.jl")
include("variable_bounding.jl")
include("constraint_bounding.jl")


"""
Check if a variable is integer (including binary).
"""
is_int(x::Char) = x == 'I' || x == 'B'


function split_by_sign(coefs::Vector{Float64})
    positive_indices = Int[]
    negative_indices = Int[]
    for i in eachindex(coefs)
        coef = coefs[i]
        if coef > 0
            push!(positive_indices, i)
        else
            push!(negative_indices, i)
        end
    end
    positive_indices, negative_indices
end


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
- Union synonyms class that are fixed to `fixed`.
- Return `(to_remove => representative)`
- All of which are not fixed.
- `to_remove` != `representative`.
- All `to_remove` can be safely removed.
"""
function get_synonym_redirection(
        synonyms::Dict{Int, Int}, fixed::Set{Int},
        lbs::Vector{Float64}, ubs::Vector{Float64}
    )
    # synonyms may contain x => y, y => z, a => y

    synonym_classes = Dict{Int, Set{Int}}()

    for (a, b) in synonyms
        update_equivalence_classes(synonym_classes, a, b)
    end

    redirection = Dict{Int, Int}()

    for eq_class in values(synonym_classes)
        fixed_lot = intersect(eq_class, fixed)
        if !isempty(fixed_lot)
            # As long as there is one fixed, all eq_class are fixed.
            the_fixed_one = first(fixed_lot)

            for x in eq_class
                if !(x in fixed)
                    # Update bounds.
                    lbs[x] = lbs[the_fixed_one]
                    ubs[x] = ubs[the_fixed_one]
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

    redirection
end


function domain_propagate(
        m, senses::Vector{Char}, rhs_s::Vector{Float64},
        lbs::Vector{Float64}, ubs::Vector{Float64}, vtypes::Vector{Char}
    )
    fixed = Set{Int}()
    redundant_constraints = Set{Int}()
    synonyms = Dict{Int, Int}()
    tighten_bounds(lbs, ubs, vtypes)
    updated = true
    pass = 0
    while updated
        pass += 1
        info(LOGGER, "Pass $pass starts.")

        variable_fixing_stats = apply_variable_fixing(m, fixed, lbs, ubs, rhs_s)
        #synonym_substitution_stats = apply_synonym_substitution(m, senses, rhs_s, lbs, ubs, vtypes, redundant_constraints, synonyms)
        synonym_substitution_stats = SynonymSubstitutionStats(0)
        variable_bounding_stats = apply_variable_bounding(m, senses, rhs_s, lbs, ubs, vtypes)
        constraint_bounding_stats = apply_constraint_bounding(m, senses, rhs_s, lbs, ubs, redundant_constraints)

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

        info(LOGGER, "Pass $pass $(pass_stats).")
    end
    #synonym_substitution_stats = apply_synonym_substitution(m, senses, rhs_s, lbs, ubs, vtypes, redundant_constraints, synonyms)
    #synonym_substitution_stats = apply_synonym_substitution(m, senses, rhs_s, lbs, ubs, vtypes, redundant_constraints, synonyms)
    synonym_redirection = get_synonym_redirection(synonyms, fixed, lbs, ubs)

    num_fixed = length(fixed)
    num_synonyms_pair = length(synonym_redirection)
    num_redundant_constraints = length(redundant_constraints)

    num_effective_variables = length(vtypes) - num_fixed
    # Here do not considering the remaining part of synonyms.
    num_effective_constraints = length(rhs_s) - num_redundant_constraints

    info(LOGGER, "Finally #fixed=$(num_fixed), #redundant_constraints=$(num_redundant_constraints), #synonyms=$(num_synonyms_pair).")
    info(LOGGER, "Finally #effected_variables=$(num_effective_variables), #effective_constraints=$(num_effective_constraints).")
    fixed, redundant_constraints, synonym_redirection
end


"""
Called by `tighten_bounds` only.
"""
function tighten_ub(col::Int, ubs::Vector{Float64}, vtype::Char)
    ub = ubs[col]
    if is_int(vtype)
        x = floor(ub)
        if x < ub
            debug(LOGGER, "Variable $(col) ub: $ub -> $x")
            ubs[col] = x
            return true
        end
    end
    false
end

"""
Called by `tighten_bounds` only.
"""
function tighten_lb(col::Int, lbs::Vector{Float64}, vtype::Char)
    lb = lbs[col]
    if is_int(vtype)
        x = ceil(lb)
        if x > lb
            debug(LOGGER, "Variable $(col) lb: $lb -> $x")
            lbs[col] = x
            return true
        end
    end
    false
end


function tighten_bounds(lbs::Vector{Float64}, ubs::Vector{Float64}, vtypes::Vector{Char})
    debug(LOGGER, "Start initial bounds reductions.")
    for col in eachindex(lbs)
        vtype = vtypes[col]
        tighten_lb(col, lbs, vtype)
        tighten_ub(col, ubs, vtype)
    end
end




function build_model(
        m, vtypes::Vector{Char}, lbs::Vector{Float64}, ubs::Vector{Float64},
        senses::Vector{Char}, rhs_s::Vector{Float64},
        fixed::Set{Int}, redundant_constraints::Set{Int},
        synonym_redirection::Dict{Int, Int},
        essential_variables::Set{Int}
    )
    env = Gurobi.Env()
    model = Gurobi.Model(env, "presolved")

    vtypes_new, lbs_new, ubs_new, variable_mapping = reduce_model_variables(
        fixed, synonym_redirection, vtypes, lbs, ubs, essential_variables
    )
    A, rhs_new, senses_new, constraint_mapping = reduce_model_constraints(
        length(vtypes_new), variable_mapping, m, redundant_constraints, rhs_s, senses
    )

    add_vars!(model, vtypes_new, zeros(length(vtypes_new)), lbs_new, ubs_new)
    update_model!(model)
    add_constrs!(model, A, senses_new, rhs_new)
    update_model!(model)
    model, variable_mapping, constraint_mapping
end


"""
- Called by `reduce_model_variables` only.
- We only care about variables that are fixed and essential.
- Return `to_remove => representative`.
- `to_remove` != `representative`.
- All `to_remove` can be safely removed.
"""
function get_fixed_essential_variable_redirection(fixed::Set{Int}, essential_variables::Set{Int}, lbs::Vector{Float64})
    to_compress = intersect(fixed, essential_variables)
    # Nothing in to_compress is in removable_fixed.
    redirection = Dict{Int, Int}()

    synonyms_by_value = Dict{Float64, Set{Int}}()
    for x in to_compress
        v = lbs[x]
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


function reduce_model_variables(
        fixed::Set{Int}, synonym_redirection::Dict{Int, Int},
        vtypes::Vector{Char}, lbs::Vector{Float64}, ubs::Vector{Float64},
        essential_variables::Set{Int}
    )
    num_cols = length(vtypes)
    # In best case, all variables in fixed can be removed, as constraints have no references to them.

    removable_fixed = setdiff(fixed, essential_variables)
    redirection, num_extra_kept = get_fixed_essential_variable_redirection(fixed, essential_variables, lbs)
    # All variables in the left one is fixed.
    # All variables in the right one is not fixed.
    # So there are no key conflictions.
    merge!(redirection, synonym_redirection)

    num_to_remove = length(removable_fixed) + length(redirection)

    if num_extra_kept > 0
        info(LOGGER, "Could have removed $(num_extra_kept) more variables if essential_variables were empty.")
    end

    num_cols_new = num_cols - num_to_remove
    vtypes_new = Array(Char, num_cols_new)
    lbs_new = Array(Float64, num_cols_new)
    ubs_new = Array(Float64, num_cols_new)

    variable_mapping = Dict{Int, Int}()

    i = 0
    for col in 1:num_cols
        if col in removable_fixed
            continue
        end
        if haskey(redirection, col)
            representative = redirection[col]
            # Since representative < col, it has already a mapping.
            variable_mapping[col] = variable_mapping[representative]
            continue
        end
        i += 1
        vtypes_new[i] = vtypes[col]
        lbs_new[i] = lbs[col]
        ubs_new[i] = ubs[col]
        variable_mapping[col] = i
    end
    vtypes_new, lbs_new, ubs_new, variable_mapping
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

        I, J, V = findnz(m[row, :])
        for (col, coef) in zip(J, V)
            A[i, variable_mapping[col]] = coef
        end
    end

    A, rhs_new, senses_new, constraint_mapping
end


function preprocess(model::Gurobi.Model, essential_variables::Set{Int}=Set{Int}())
    if is_qp(model) || is_qcp(model)
        error("Only works with MILP!")
    end

    lbs = Gurobi.lowerbounds(model)
    ubs = Gurobi.upperbounds(model)
    vtypes = Gurobi.get_charattrarray(model, "VType", 1, num_vars(model))
    rhs_s = Gurobi.get_dblattrarray(model, "RHS", 1, num_constrs(model))
    senses = Gurobi.get_charattrarray(model, "Sense", 1, num_constrs(model))

    #if length(lbs) < 10
    #    @show lbs
    #    @show ubs
    #    @show vtypes
    #    @show rhs_s
    #    @show senses
    #    println()
    #end

    m = get_constrmatrix(model)
    fixed, redundant_constraints, synonym_redirection = domain_propagate(m, senses, rhs_s, lbs, ubs, vtypes)

    presolved_model, variable_mapping, constraint_mapping = build_model(
        m, vtypes, lbs, ubs, senses, rhs_s,
        fixed, redundant_constraints, synonym_redirection, essential_variables
    )
    presolved_model, variable_mapping, constraint_mapping
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