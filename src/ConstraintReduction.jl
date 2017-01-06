module ConstraintReduction

using MiniLogging
using Parameters

const LOGGER = get_logger(current_module())

using ..IterSparseMatrix
using ..Variables
using ..Rules
using ..Models

const RULE = :constraint_reduction

immutable Stats <: Statistics{Val{RULE}}
    redundant_constraints::Int
end


"""
- Ref 3.1
- This also covers empty lhs.
"""
function Rules.apply_rule(
        ::Type{Val{RULE}}, model::DecomposedModel, m_info::ModelInfo;
        ϵ::Float64=10e-6
    )::Stats
    @unpack m, variables, rhs_s, senses = model
    @unpack redundant_constraints = m_info

    num_redundant_constraints = 0

    for (row, row_element) in enumerate(m, Val{:row})
        if row in redundant_constraints
            continue
        end

        sense = senses[row]
        rhs = rhs_s[row]

        lhs_split = SplitBySign(row_element)
        max_activity = get_max_activity(variables, lhs_split)
        min_activity = get_min_activity(variables, lhs_split)

        if sense == '<'
            if max_activity <= rhs + ϵ
                remove_constraint(m, row, rhs_s, redundant_constraints)
                num_redundant_constraints += 1
            elseif min_activity > rhs + ϵ
                error("Infeasible!")
            end
        else
            if min_activity >= rhs - ϵ && max_activity <= rhs + ϵ
                remove_constraint(m, row, rhs_s, redundant_constraints)
                num_redundant_constraints += 1
            elseif min_activity > rhs + ϵ || max_activity < rhs - ϵ
                error("Infeasible!")
            end
        end

        # TODO sense == '='
    end
    Stats(num_redundant_constraints)
end

end