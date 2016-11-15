const simple_rule = Dict(
    # x + y >= 1
    (false, true, true, true) => (1, 1, '>', 1),
    # x - y >= 0
    (true, false, true, true) => (1, -1, '>', 0),
    # x - y <= 0
    (true, true, false, true) => (1, -1, '<', 0),
    # x + y <= 1
    (true, true, true, false) => (1, 1, '<', 1),
)


function apply_constraint_simplification(
        m, senses::Vector{Char}, rhs_s::Vector{Float64},
        variables::Vector{Variable},
        redundant_constraints::Set{Int}
    )
    num_simplified_constraints = 0

    # m is modified row by row.
    for (row, row_element) in enumerate(m, Val{:row})
        sense = senses[row]
        rhs = rhs_s[row]

        if row in redundant_constraints
            continue
        end

        if isempty(row_element)
            push!(redundant_constraints, row)
            continue
        end

        if length(row_element) != 2
            continue
        end

        (col1, coef1), (col2, coef2) = enumerate(row_element)

        if coef1 == 0 || coef2 == 0
            continue
        end

        x1 = variables[col1]
        x2 = variables[col2]

        if !(is_int(x1) && is_int(x2) && x1.lb == 0 && x1.ub == 1 && x2.lb == 0 && x2.ub == 1)
            continue
        end

        if sense == '<'
            case_00 = 0 <= rhs
            case_01 = coef2 <= rhs
            case_10 = coef1 <= rhs
            case_11 = coef1 + coef2 <= rhs
        elseif sense == '>'
            case_00 = 0 >= rhs
            case_01 = coef2 >= rhs
            case_10 = coef1 >= rhs
            case_11 = coef1 + coef2 >= rhs
        else
            case_00 = 0 == rhs
            case_01 = coef2 == rhs
            case_10 = coef1 == rhs
            case_11 = coef1 + coef2 == rhs
        end

        k = case_00, case_01, case_10, case_11
        if !haskey(simple_rule, k)
            continue
        end

        coef1_new, coef2_new, sense_new, rhs_new = simple_rule[k]
        if (coef1, coef2, sense, rhs) == (coef1_new, coef2_new, sense_new, rhs_new)
            continue
        end

        before = "$coef1 * $x1 + $coef2 * $x2 $sense $rhs"
        after = "$(coef1_new) * x + $(coef2_new) * y $(sense_new) $(rhs_new)"
        m[row, col1] = coef1_new
        m[row, col2] = coef2_new
        senses[row] = sense_new
        rhs_s[row] = rhs_new
        debug(LOGGER, "Simplify constraint $row: $before to $after")
        num_simplified_constraints += 1
    end

    ConstraintSimplificationStats(num_simplified_constraints)
end

