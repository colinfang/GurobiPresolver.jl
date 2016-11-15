function apply_variable_fixing(
        m, fixed::Set{Int},
        variables::Vector{Variable},
        rhs_s::Vector{Float64}
    )::VariableFixingStats
    num_fixed_variables = 0
    num_simplified_terms = 0
    for variable in variables
        if variable.id in fixed
            continue
        end

        if is_fixed(variable)
            push!(fixed, variable.id)
            num_fixed_variables += 1
            debug(LOGGER, "Detect fixed $variable")
            num_simplified_terms += substitute_fixed_variable(m, variable, rhs_s)
        end
    end
    VariableFixingStats(num_fixed_variables, num_simplified_terms)
end

"""
- Simplify constraints for fixed variables.
- Return number of simplified terms.
- Called by `apply_variable_fixing` only.
"""
function substitute_fixed_variable(m, variable::Variable, rhs_s::Vector{Float64})::Int
    ret = 0
    rows = rowvals(m)
    vals = nonzeros(m)

    for i in nzrange(m, variable.id)
        row = rows[i]
        coef = vals[i]
        rhs_s[row] -= coef * variable.lb
        vals[i] = 0
        ret += 1
        debug(LOGGER, "Simplify a term $coef * X[$(variable.id)], in constraint $row")
    end
    ret
end
