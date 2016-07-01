function apply_variable_fixing(
        m, fixed::Set{Int},
        lbs::Vector{Float64}, ubs::Vector{Float64},
        rhs_s::Vector{Float64}
    )
    num_fixed_variables = 0
    num_simplified_terms = 0
    for col in eachindex(lbs)
        if col in fixed
            continue
        end
        lb = lbs[col]
        ub = ubs[col]
        if lb == ub
            push!(fixed, col)
            num_fixed_variables += 1
            debug(LOGGER, "Detected fixed Variable $col = $lb.")
            num_simplified_terms += substitute_fixed_variable(m, col, lb, rhs_s)
        elseif lb > ub
            error("Infeasible!")
        end
    end
    VariableFixingStats(num_fixed_variables, num_simplified_terms)
end

"""
- Simplify constraints for fixed variables.
- Return number of simplified terms.
- Called by `apply_variable_fixing` only.
"""
function substitute_fixed_variable(m, col::Int, v::Float64, rhs_s::Vector{Float64})
    ret = 0
    rowval = rowvals(m)
    nzval = nonzeros(m)

    for i in nzrange(m, col)
        row = rowval[i]
        coef = nzval[i]
        rhs_s[row] -= coef * v
        ret += 1
        debug(LOGGER, "Simplified a term $coef * X[$col], in constraint $(row).")
    end

    # Cannot put this in the above loop, as it would change m.rowval, m.nzval.
    m[:, col] = 0.0
    ret
end