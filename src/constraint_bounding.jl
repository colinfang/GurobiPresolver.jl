function sum_product(
        indices::Vector{Int}, bounds::Vector{Float64},
        cols::Vector{Int}, coefs::Vector{Float64}
    )
    ret = 0.0
    for i in indices
        col = cols[i]
        coef = coefs[i]
        bound = bounds[col]
        ret += coef * bound
    end
    ret
end


function get_constraint_lb(positive_indices, negative_indices, lbs, ubs, cols, coefs)
    sum_product(positive_indices, lbs, cols, coefs) + sum_product(negative_indices, ubs, cols, coefs)
end

function get_constraint_ub(positive_indices, negative_indices, lbs, ubs, cols, coefs)
    sum_product(positive_indices, ubs, cols, coefs) + sum_product(negative_indices, lbs, cols, coefs)
end

"""
- Fix the variables to one of the bounds.
- One the next pass `variable_fixing` those varibles will be detected as fixed.
"""
function fix_to_constraint_lb(
        positive_indices::Vector{Int}, negative_indices::Vector{Int},
        lbs::Vector{Float64}, ubs::Vector{Float64}, cols::Vector{Int}
    )
    for i in positive_indices
        col = cols[i]
        if lbs[col] > ubs[col]
            error("Infeasible!")
        elseif lbs[col] < ubs[col]
            # Bounds are already integers if variable type is integer.
            debug(LOGGER, "Variable $(col) is fixed to lb = $(lbs[col])")
            ubs[col] = lbs[col]
        end
    end

    for i in negative_indices
        col = cols[i]
        if lbs[col] > ubs[col]
            error("Infeasible!")
        elseif lbs[col] < ubs[col]
            # Bounds are already integers if variable type is integer.
            debug(LOGGER, "Variable $(col) is fixed to ub = $(ubs[col])")
            lbs[col] = ubs[col]
        end
    end
end

"""
- Fix the variables to one of the bounds.
- One the next pass `variable_fixing` those varibles will be detected as fixed.
"""
function fix_to_constraint_ub(
        positive_indices::Vector{Int}, negative_indices::Vector{Int},
        lbs::Vector{Float64}, ubs::Vector{Float64}, cols::Vector{Int}
    )
    for i in negative_indices
        col = cols[i]
        if lbs[col] > ubs[col]
            error("Infeasible!")
        elseif lbs[col] < ubs[col]
            # Bounds are already integers if variable type is integer.
            debug(LOGGER, "Variable $(col) is fixed to lb = $(lbs[col])")
            ubs[col] = lbs[col]
        end
    end

    for i in positive_indices
        col = cols[i]
        if lbs[col] > ubs[col]
            error("Infeasible!")
        elseif lbs[col] < ubs[col]
            # Bounds are already integers if variable type is integer.
            debug(LOGGER, "Variable $(col) is fixed to ub = $(ubs[col])")
            lbs[col] = ubs[col]
        end
    end
end

function remove_constraint(m, row::Int, rhs_s::Vector{Float64})
    m[row, :] = 0.0
    rhs_s[row] = 0.0
    debug(LOGGER, "Removed redundant constraint $row.")
end


function apply_constraint_bounding(
        m, senses::Vector{Char}, rhs_s::Vector{Float64},
        lbs::Vector{Float64}, ubs::Vector{Float64},
        redundant_constraints::Set{Int}
    )
    mt = transpose(m)
    mt_nzval = nonzeros(mt)
    mt_rowval = rowvals(mt)
    num_redundant_constraints = 0

    # m is modified row by row.
    for row in 1:size(m, 1)
        if row in redundant_constraints
            continue
        end

        mt_col = row
        mt_nzrange = nzrange(mt, mt_col)
        if isempty(mt_nzrange)
            # Empty column in mt => empty row in m.
            # Constraint may be deleted by apply_variable_fixing.
            push!(redundant_constraints, row)
            continue
        end

        cols = mt_rowval[mt_nzrange]
        coefs = mt_nzval[mt_nzrange]

        sense = senses[row]
        rhs = rhs_s[row]

        positive_indices, negative_indices = split_by_sign(coefs)

        constraint_ub = get_constraint_ub(positive_indices, negative_indices, lbs, ubs, cols, coefs)
        constraint_lb = get_constraint_lb(positive_indices, negative_indices, lbs, ubs, cols, coefs)

        if sense == '<'
            if rhs >= constraint_ub
                remove_constraint(m, row, rhs_s)
                push!(redundant_constraints, row)
                num_redundant_constraints += 1
            elseif rhs == constraint_lb
                fix_to_constraint_lb(positive_indices, negative_indices, lbs, ubs, cols)
                remove_constraint(m, row, rhs_s)
                push!(redundant_constraints, row)
                num_redundant_constraints += 1
            elseif rhs < constraint_lb
                error("Infeasible!")
            end
        elseif sense == '>'
            if rhs <= constraint_lb
                remove_constraint(m, row, rhs_s)
                push!(redundant_constraints, row)
                num_redundant_constraints += 1
            elseif rhs == constraint_ub
                fix_to_constraint_ub(positive_indices, negative_indices, lbs, ubs, cols)
                remove_constraint(m, row, rhs_s)
                push!(redundant_constraints, row)
                num_redundant_constraints += 1
            elseif rhs > constraint_ub
                error("Infeasible!")
            end
        end

        # TODO sense == '='
    end
    ConstraintBoundingStats(num_redundant_constraints)
end