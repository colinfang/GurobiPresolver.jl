module VariableBounding

using MiniLogging
using Parameters

const LOGGER = get_logger(current_module())

using ..IterSparseMatrix
using ..Variables
using ..Rules
using ..Models

const RULE = :variable_bounding

immutable Stats <: Statistics{Val{RULE}}
    row_updates::Int
    bounds_updates::Int
end


"""
- Update variables bounds for constraint `AiXi <= c`.
- `coef` isn't 0.
"""
function update_bound_less(
        variables::Vector{Variable}, col::Int,
        coef::Float64, rhs::Float64,
        lhs::SplitBySign
    )::Bool
    v = get_min_activity(variables, lhs, col)

    x = (rhs - v) / coef
    if coef > 0
        tighten_ub(variables[col], x)
    else
        tighten_lb(variables[col], x)
    end
end

"""
Update variables bounds for constraint `AiXi >= c`.
"""
function update_bound_greater(
        variables::Vector{Variable}, col::Int,
        coef::Float64, rhs::Float64,
        lhs::SplitBySign
    )::Bool
    v = get_max_activity(variables, lhs, col)

    x = (rhs - v) / coef
    if coef > 0
        tighten_lb(variables[col], x)
    else
        tighten_ub(variables[col], x)
    end
end


"""
Ref 3.2
"""
function Rules.apply_rule(
        ::Type{Val{RULE}}, model::DecomposedModel, m_info::ModelInfo
    )::Stats
    @unpack m, variables, rhs_s, senses = model
    @unpack redundant_constraints = m_info

    num_row_updates = 0
    num_bounds_updates = 0

    for (row, row_element) in enumerate(m, Val{:row})
        if row in redundant_constraints
            continue
        end

        num_bounds_updates_per_row = 0
        sense = senses[row]
        rhs = rhs_s[row]

        try
            lhs_split = SplitBySign(row_element)

            for (col, coef) in nz_terms(row_element)
                if sense == '<' || sense == '='
                    if update_bound_less(variables, col, coef, rhs, lhs_split)
                        num_bounds_updates_per_row += 1
                    end
                end
                # TODO combine `=`.
                # Why Ref doesn't say about `=`.
                if sense == '='
                    if update_bound_greater(variables, col, coef, rhs, lhs_split)
                        num_bounds_updates_per_row += 1
                    end
                end
            end

            if num_bounds_updates_per_row > 0
                num_row_updates += 1
                num_bounds_updates += num_bounds_updates_per_row
                @debug(LOGGER, "Updated $(num_bounds_updates_per_row) bounds on constraint $row")
            end
        catch
            s = stringify_constraint(model, row, row_element)
            println("$s in constraint $row")
            rethrow()
        end
    end
    Stats(num_row_updates, num_bounds_updates)
end

end