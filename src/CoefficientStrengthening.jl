module CoefficientStrengthening

using MiniLogging
using Parameters

const LOGGER = get_logger(current_module())

using ..IterSparseMatrix
using ..Variables
using ..Rules
using ..Models

const RULE = :coefficient_strengthening

immutable Stats <: Statistics{Val{RULE}}
    row_updates::Int
    num_coefs_updates::Int
end

"""
Ref 3.3
"""
function Rules.apply_rule(
        ::Type{Val{RULE}}, model::DecomposedModel, m_info::ModelInfo;
        ϵ::Float64=10e-6
    )::Stats
    @unpack m, variables, rhs_s, senses = model
    @unpack redundant_constraints = m_info

    num_row_updates = 0
    num_coefs_updates = 0

    for (row, row_element) in enumerate(m, Val{:row})
        if row in redundant_constraints
            continue
        end

        num_coefs_updated_per_row = 0
        sense = senses[row]
        rhs = rhs_s[row]

        lhs_split = SplitBySign(row_element)
        max_activity = get_max_activity(variables, lhs_split)

        # `max_activity <= rhs + ϵ` => constraint reduction
        if sense == '<' && !(max_activity <= rhs + ϵ)
            for (col, coef) in nz_terms(row_element)
                # From Ref,
                # coef >= d = rhs - max_activity + coef > 0
                # The left inequality is checked already.
                x = variables[col]
                if !is_int(x)
                    continue
                end
                d = rhs - max_activity + coef
                # Make sure the updated constraint dominates.
                if d <= ϵ
                    continue
                end
                # Here always update.
                # `coef_new` is always closer to 0, without changing sign.
                if coef > 0
                    coef_new = coef - d
                    rhs_new = rhs - d * x.ub
                else
                    coef_new = coef + d
                    rhs_new = rhs + d * x.lb
                end
                # Actual update.
                m[row, col] = coef_new
                rhs_s[row] = rhs_new
                num_coefs_updated_per_row += 1
                # Update values.
                if coef > 0
                    max_activity = max_activity - d * x.ub
                else
                    max_activity = max_activity + d * x.lb
                end
                rhs = rhs_new
            end
        end
        # Does it work with `=`?

        if num_coefs_updated_per_row > 0
            num_row_updates += 1
            num_coefs_updates += num_coefs_updated_per_row
            @debug(LOGGER, "Updated $(num_coefs_updated_per_row) bounds on constraint $row")
        end
    end

    Stats(num_row_updates, num_coefs_updates)
end

end