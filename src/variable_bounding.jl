function sum_product(
        indices::Vector{Int}, bounds::Vector{Float64}, ignore_col::Int,
        cols::Vector{Int}, coefs::Vector{Float64}
    )
    ret = 0.0
    for i in indices
        col = cols[i]
        if col != ignore_col
            coef = coefs[i]
            bound = bounds[col]
            ret += coef * bound
        end
    end
    ret
end


"""
Update variables bounds for constraint `AiXi <= c`.
"""
function update_bound_less(
        idx, rhs, positive_indices, negative_indices, lbs, ubs,
        cols::Vector{Int}, coefs::Vector{Float64}, vtypes::Vector{Char}
    )
    col = cols[idx]
    coef = coefs[idx]
    vtype = vtypes[col]

    v = sum_product(positive_indices, lbs, col, cols, coefs) +
        sum_product(negative_indices, ubs, col, cols, coefs)

    x = (rhs - v) / coef
    if coef > 0
        tighten_ub(col, x, ubs, vtype)
    else
        tighten_lb(col, x, lbs, vtype)
    end
end

"""
Update variables bounds for constraint `AiXi >= c`.
"""
function update_bound_greater(
        idx, rhs, positive_indices, negative_indices, lbs, ubs,
        cols::Vector{Int}, coefs::Vector{Float64}, vtypes::Vector{Char}
    )
    col = cols[idx]
    coef = coefs[idx]
    vtype = vtypes[col]

    v = sum_product(positive_indices, ubs, col, cols, coefs) +
        sum_product(negative_indices, lbs, col, cols, coefs)

    x = (rhs - v) / coef
    if coef > 0
        tighten_lb(col, x, lbs, vtype)
    else
        tighten_ub(col, x, ubs, vtype)
    end
end

"""
Called by `update_bound...` & `apply_synonym_substitution` only.
"""
function tighten_ub(col::Int, x::Float64, ubs::Vector{Float64}, vtype::Char)
    ub = ubs[col]
    if x < ub
        if is_int(vtype)
            y = floor(x)
            debug(LOGGER, "Variable $(col) ub: $ub -> $x -> $y")
            ubs[col] = y
        else
            debug(LOGGER, "Variable $(col) ub: $ub -> $x")
            ubs[col] = x
        end
        true
    else
        false
    end
end

"""
Called by `update_bound...` & `apply_synonym_substitution` only.
"""
function tighten_lb(col::Int, x::Float64, lbs::Vector{Float64}, vtype::Char)
    lb = lbs[col]
    if x > lb
        if is_int(vtype)
            y = ceil(x)
            debug(LOGGER, "Variable $(col) lb: $lb -> $x -> $y")
            lbs[col] = y
        else
            debug(LOGGER, "Variable $(col) lb: $lb -> $x")
            lbs[col] = x
        end
        true
    else
        false
    end
end


function apply_variable_bounding(
        m, senses::Vector{Char}, rhs_s::Vector{Float64},
        lbs::Vector{Float64}, ubs::Vector{Float64}, vtypes::Vector{Char}
    )
    mt = transpose(m)
    mt_nzval = nonzeros(mt)
    mt_rowval = rowvals(mt)
    num_row_updates = 0
    num_bounds_updates = 0

    # m is not modified in the following loop.
    for row in 1:size(m, 1)
        mt_col = row
        mt_nzrange = nzrange(mt, mt_col)
        if isempty(mt_nzrange)
            # Empty column in mt => empty row in m.
            # Constraint may be deleted by apply_variable_fixing.
            continue
        end
        # Should I bring in redundant_constraints here as well?

        cols = mt_rowval[mt_nzrange]
        coefs = mt_nzval[mt_nzrange]

        sense = senses[row]
        rhs = rhs_s[row]

        positive_indices, negative_indices = split_by_sign(coefs)
        num_bounds_updates_per_row = 0

        if sense == '<' || sense == '='
            for i in eachindex(cols)
                col = cols[i]
                if update_bound_less(i, rhs, positive_indices, negative_indices, lbs, ubs, cols, coefs, vtypes)
                    num_bounds_updates_per_row += 1
                end
            end
        end

        if sense == '>' || sense == '='
            for i in eachindex(cols)
                col = cols[i]
                if update_bound_greater(i, rhs, positive_indices, negative_indices, lbs, ubs, cols, coefs, vtypes)
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