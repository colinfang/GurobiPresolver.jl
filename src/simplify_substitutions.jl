# Input
# - It is possible `representative` turns out to be `to_remove` in another entry.
# - But no cyclic references.


"""

- Called by `domain_propagate` only.
"""
function simplify_substitutions(model::DecomposedModel, m_info::ModelInfo)
    flatten(model, m_info)
    constant_folding(model, m_info)
end


"""
- Redirect `x => y`, `y => z`, `a => y` to `a => z`, `y => z`, `x => z`
- E.g. variables in `representative` shouldn't apear in the `to_remove` in another entry.
"""
function flatten(model::DecomposedModel, m_info::ModelInfo)
    @unpack substitutions = m_info
    # `rev` so that it is more likely the variable with bigger `id`` gets substituted.
    for key_to_remove in sort(collect(keys(substitutions)), rev=true)
        key_expr = substitutions[key_to_remove]
        @debug(LOGGER, "Reference $(key_to_remove) => $(key_expr)")
        for (to_remove, expr) in substitutions
            coef = expr.coefs[key_to_remove]
            if coef != 0
                @debug(LOGGER, "Before $(to_remove) => $expr")
                expr.coefs[key_to_remove] = 0
                expr.coefs[:] += coef * key_expr.coefs
                expr.c += coef * key_expr.c
                @debug(LOGGER, "After $(to_remove) => $expr")
            end
        end
    end
end



"""
- It makes sure keys in `substitutions` are all mutually exclusive with `fixed`.
- Remove entries that have `to_remove` in `fixed`.
- Replace fix variables with constants in the `expr.coefs`.
- If then `to_remove` turns out to be constant,
- Move it to `fixed` & update bounds & remove the entry.
"""
function constant_folding(model::DecomposedModel, m_info::ModelInfo)
    @unpack variables = model
    @unpack fixed, substitutions = m_info

    num_subs_old = length(substitutions)
    num_fixed_old = length(fixed)

    # Deal with fixed values in `to_remove`.
    # Make a copy for mutation.
    for x in collect(keys(substitutions))
        if x in fixed
            delete!(substitutions, x)
        end
    end

    # Deal with fixed values in `expr`.
    # Make a copy for mutation.
    for (to_remove, expr) in copy(substitutions)
        flag = false
        ss = string(expr)
        for (col, coef) in nz_terms(expr.coefs)
            if col in fixed
                variable = variables[col]
                expr.c += coef * variable.lb
                expr.coefs[col] = 0
                @debug(LOGGER, "Replaced $variable with constant")
                flag = true
            end
        end

        if flag
            @debug(LOGGER, "constant_folding: $(to_remove) => $ss == $expr")
            # Check if `expr` evaluate as constant.
            if length(collect(nz_terms(expr.coefs))) == 0
                variable = variables[to_remove]
                # Use these functions for logging & feasibility check.
                tighten_ub(variable, expr.c)
                tighten_lb(variable, expr.c)
                @debug(LOGGER, "Detect fixed $variable")
                push!(fixed, to_remove)
                delete!(substitutions, to_remove)
            end
        end
    end

    @info(LOGGER, "constant_folding #substitutions $(num_subs_old) => $(length(substitutions)), $(num_fixed_old) => $(length(fixed))")
end