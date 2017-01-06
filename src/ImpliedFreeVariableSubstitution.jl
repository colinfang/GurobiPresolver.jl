module ImpliedFreeVariableSubstitution

using MiniLogging
using Parameters

const LOGGER = get_logger(current_module())
using ..IterSparseMatrix
using ..Variables
using ..Rules
using ..Models

const RULE = :implied_free_variable_substitution

immutable Stats <: Statistics{Val{RULE}}
    redundant_constraints::Int
end

"""
- Update implied variables bounds for constraint `AiXi <= c`.
- `coef` isn't 0.
"""
function update_implied_bound!(
        lbs::Vector{Float64}, ubs::Vector{Float64},
        col::Int, coef::Float64, rhs::Float64,
        variables::Vector{Variable}, lhs::SplitBySign
    )
    v = get_min_activity(variables, lhs, col)

    x = (rhs - v) / coef
    if coef > 0
        ubs[col] = min(ubs[col], x)
    else
        lbs[col] = max(lbs[col], x)
    end
end

function get_implied_bounds(model, m_info)
    @unpack m, variables, rhs_s, senses = model
    @unpack redundant_constraints = m_info

    implied_lbs = fill(-Inf, length(variables))
    implied_ubs = fill(Inf, length(variables))

    for (row, row_element) in enumerate(m, Val{:row})
        if row in redundant_constraints
            continue
        end

        sense = senses[row]
        rhs = rhs_s[row]

        lhs_split = SplitBySign(row_element)

        for (col, coef) in nz_terms(row_element)
            if sense == '<' || sense == '='
                update_implied_bound!(
                    implied_lbs, implied_ubs,
                    col, coef, rhs,
                    variables, lhs_split
                )
            end
        end
    end
    implied_lbs, implied_ubs
end


function get_implied_free_variables(model::DecomposedModel, m_info::ModelInfo, implied_lbs, implied_ubs)
    @unpack m, variables = model
    @unpack fixed, substitutions = m_info

    ret = Int[]
    for (col, col_element) in enumerate(m, Val{:col})
        if col in fixed || haskey(substitutions, col)
            continue
        end

        x = variables[col]
        if implied_lbs[col] < x.lb || implied_ubs[col] > x.ub
            continue
        end
        # `x` is an implied free variable.
        push!(ret, col)
    end
    @debug(LOGGER, "Found $(length(ret)) free variables")
    ret
end

immutable ReferenceRow
    id::Int
    expr::LinearExpression
    # `row`, `coef` of the variable that are about to be substituted (excluding row `id`).
    substituted::Vector{Tuple{Int, Float64}}
end

function get_reference_row(
        model::DecomposedModel, col::Int,
        redundant_constraints::Set{Int}
    )
    @unpack m, senses, rhs_s = model
    col_element =  m[:, col]
    max_coef_col_wise = maximum(abs(col_element))

    # Find a suitable equation that we can use to substitute.
    reference_row = nothing

    for (row, coef) in nz_terms(col_element)
        if row in redundant_constraints
            continue
        end

        if senses[row] != '='
            continue
        end
        # This is expansive, don't do it if unnecessary.
        row_element = m[row, :]
        # No need to be very accurate (i.e. `countnz``).
        # And also gets better in the next iteration.
        # A threadshold for fill-in.
        if nnz(row_element) > 3
            continue
        end
        # Numerical safe guard
        # TODO: Can we speed it up?
        if abs(coef) < 0.01 * min(max_coef_col_wise, maximum(abs(row_element)))
            continue
        end
        # Get the first suitable row as reference.
        substituted = [(r, c) for (r, c) in nz_terms(col_element) if r != row]

        expr = LinearExpression(row_element, col, rhs_s[row])
        reference_row = ReferenceRow(row, expr, substituted)
        @debug(LOGGER, "Detect $col => $expr using constraint $row")
        break
    end

    reference_row
end

"""
- Ref 4.5
- It is possible `representative` turns out to be `to_remove` in another entry.
- But no cyclic references.
"""
function Rules.apply_rule(
        ::Type{Val{RULE}}, model::DecomposedModel, m_info::ModelInfo
    )::Stats
    @unpack m, variables, rhs_s, senses = model
    @unpack redundant_constraints, substitutions = m_info

    num_redundant_constraints = 0

    implied_lbs, implied_ubs = get_implied_bounds(model, m_info)
    implied_free_variables = get_implied_free_variables(model, m_info, implied_lbs, implied_ubs)

    for free_variable in implied_free_variables
        reference_row = get_reference_row(model, free_variable, redundant_constraints)

        if reference_row == nothing
            continue
        end

        for (row, coef) in reference_row.substituted
            s = stringify_constraint(model, row)
            @debug(LOGGER, "Before $s in constraint $row")
            m[row, :] += reference_row.expr.coefs * coef
            rhs_s[row] -= reference_row.expr.c * coef
            s = stringify_constraint(model, row)
            @debug(LOGGER, "After $s in constraint $row")
        end

        m[:, free_variable] = 0
        @debug(LOGGER, "Remove in constraint $(reference_row.id)")
        remove_constraint(m, reference_row.id, rhs_s, redundant_constraints)
        @debug(LOGGER, "Expr: ", reference_row.expr)
        substitutions[free_variable] = reference_row.expr
        num_redundant_constraints += 1
    end

    Stats(num_redundant_constraints)
end

end