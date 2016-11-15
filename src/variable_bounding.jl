"""
Update variables bounds for constraint `AiXi <= c`.
"""
function update_bound_less(
        k::Variable, coef::Float64, rhs::Float64,
        positive_terms, negative_terms
    )::Bool
    # sum empty iterator is an error.
    v = reduce(+, 0.0, (coef * x.lb for (x, coef) in positive_terms if x.id != k.id)) +
        reduce(+, 0.0, (coef * x.ub for (x, coef) in negative_terms if x.id != k.id))

    x = (rhs - v) / coef
    if coef > 0
        tighten_ub(k, x)
    elseif coef < 0
        tighten_lb(k, x)
    else
        false
    end
end

"""
Update variables bounds for constraint `AiXi >= c`.
"""
function update_bound_greater(
        k::Variable, coef::Float64, rhs::Float64,
        positive_terms, negative_terms
    )::Bool
    v = reduce(+, 0.0, (coef * x.ub for (x, coef) in positive_terms if x.id != k.id)) +
        reduce(+, 0.0, (coef * x.lb for (x, coef) in negative_terms if x.id != k.id))

    x = (rhs - v) / coef
    if coef > 0
        tighten_lb(k, x)
    elseif coef < 0
        tighten_ub(k, x)
    else
        false
    end
end


function apply_variable_bounding(
        m, senses::Vector{Char}, rhs_s::Vector{Float64},
        variables::Vector{Variable}, redundant_constraints::Set{Int}
    )::VariableBoundingStats
    num_row_updates = 0
    num_bounds_updates = 0

    # `m`` is not modified in the following loop.
    for (row, row_element) in enumerate(m, Val{:row})
        if row in redundant_constraints
            continue
        end

        num_bounds_updates_per_row = 0
        sense = senses[row]
        rhs = rhs_s[row]

        if isempty(row_element)
            if rhs > 0 && sense == '>'
                error("Infeasible!")
            end
            if rhs < 0 && sense == '<'
                error("Infeasible!")
            end
            if rhs != 0 && sense == '='
                error("Infeasible!")
            end
            push!(redundant_constraints, row)
            continue
        end

        positive_terms = Tuple{Variable, Float64}[]
        negative_terms = Tuple{Variable, Float64}[]
        for (col, coef) in enumerate(row_element)
            if coef > 0
                push!(positive_terms, (variables[col], coef))
            elseif coef < 0
                push!(negative_terms, (variables[col], coef))
            # Ignore 0
            end
        end

        for (col, coef) in enumerate(row_element)
            if sense == '<' || sense == '='
                if update_bound_less(variables[col], coef, rhs, positive_terms, negative_terms)
                    num_bounds_updates_per_row += 1
                end
            end

            if sense == '>' || sense == '='
                if update_bound_greater(variables[col], coef, rhs, positive_terms, negative_terms)
                    num_bounds_updates_per_row += 1
                end
            end
        end

        if num_bounds_updates_per_row > 0
            num_row_updates += 1
            num_bounds_updates += num_bounds_updates_per_row
            debug(LOGGER, "Updated $(num_bounds_updates_per_row) bounds on constraint $row.")
        end
    end
    VariableBoundingStats(num_row_updates, num_bounds_updates)
end