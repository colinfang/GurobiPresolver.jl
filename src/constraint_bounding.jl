"""
- Fix the variables to one of the bounds.
- One the next pass `variable_fixing` those varibles will be detected as fixed.
"""
function fix_to_constraint_lb(positive_terms, negative_terms)
    for (x, coef) in positive_terms
        tighten_to_lb(x)
    end

    for (x, coef) in negative_terms
        tighten_to_ub(x)
    end
end

function fix_to_constraint_ub(positive_terms, negative_terms)
    for (x, coef) in positive_terms
        tighten_to_ub(x)
    end

    for (x, coef) in negative_terms
        tighten_to_lb(x)
    end
end

function remove_constraint(
    m, row::Int, rhs_s::Vector{Float64},
    redundant_constraints::Set{Int}
)
    # It shouldn't modify the structure.
    m[row, :] = 0.0
    rhs_s[row] = 0.0
    debug(LOGGER, "Removed redundant constraint $row.")
    push!(redundant_constraints, row)
end


function apply_constraint_bounding(
        m, senses::Vector{Char}, rhs_s::Vector{Float64},
        variables::Vector{Variable}, redundant_constraints::Set{Int}
    )::ConstraintBoundingStats
    num_redundant_constraints = 0

    # m is modified row by row.
    for (row, row_element) in enumerate(m, Val{:row})
        if row in redundant_constraints
            continue
        end

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

        constraint_ub = reduce(+, 0.0, (coef * x.ub for (x, coef) in positive_terms)) +
            reduce(+, 0.0, (coef * x.lb for (x, coef) in negative_terms))
        constraint_lb = reduce(+, 0.0, (coef * x.lb for (x, coef) in positive_terms)) +
            reduce(+, 0.0, (coef * x.ub for (x, coef) in negative_terms))

        if sense == '<'
            if rhs >= constraint_ub
                remove_constraint(m, row, rhs_s, redundant_constraints)
                num_redundant_constraints += 1
            elseif rhs == constraint_lb
                fix_to_constraint_lb(positive_terms, negative_terms)
                remove_constraint(m, row, rhs_s, redundant_constraints)
                num_redundant_constraints += 1
            elseif rhs < constraint_lb
                error("Infeasible!")
            end
        elseif sense == '>'
            if rhs <= constraint_lb
                remove_constraint(m, row, rhs_s, redundant_constraints)
                num_redundant_constraints += 1
            elseif rhs == constraint_ub
                fix_to_constraint_ub(positive_terms, negative_terms)
                remove_constraint(m, row, rhs_s, redundant_constraints)
                num_redundant_constraints += 1
            elseif rhs > constraint_ub
                error("Infeasible!")
            end
        end

        # TODO sense == '='
    end
    ConstraintBoundingStats(num_redundant_constraints)
end