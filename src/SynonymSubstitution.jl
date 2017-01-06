module SynonymSubstitution

using MiniLogging
using Parameters

const LOGGER = get_logger(current_module())

using ..IterSparseMatrix
using ..Variables
using ..Rules
using ..Models

const RULE = :synonym_substitution

immutable Stats <: Statistics{Val{RULE}}
    synonyms_pair::Int
end


"""
- `synonyms` is `to_remove => representative`.
- `to_remove > representative`.
- It is possible `representative` turns out to be `to_remove` in another entry.
- But no cyclic references.
"""
function Rules.apply_rule(
        ::Type{Val{RULE}}, model::DecomposedModel, m_info::ModelInfo
    )::Stats
    @unpack m, variables, rhs_s, senses = model
    @unpack fixed, redundant_constraints, substitutions = m_info

    synonyms = Dict{Int, Int}()

    for (row, row_element) in enumerate(m, Val{:row})
        if !(senses[row] == '=' && rhs_s[row] == 0.0)
            continue
        end

        if row in redundant_constraints
            continue
        end

        if isempty(row_element)
            continue
        end

        terms = collect(nz_terms(row_element))
        # So cols are not in `fixed` or `substitutions` because non zeros.

        if length(terms) != 2
            continue
        end

        (col1, coef1), (col2, coef2) = terms

        if coef1 + coef2 != 0.0
            continue
        end

        # Now `col1`, `col2` are synonyms.

        representative = variables[min(col1, col2)]
        to_remove = variables[max(col1, col2)]

        if haskey(synonyms, to_remove.id)
            # In a pass, it is possible to have `c => x`, `c => y`.
            # In such case we skip till next pass.
            continue
        end

        @debug(LOGGER, "Detect synonyms pair $(to_remove) => $representative from constraint $row")

        synonyms[to_remove.id] = representative.id

        remove_constraint(m, row, rhs_s, redundant_constraints)
    end

    # Merge coefs of `to_remove` into `representative`.
    # This would change structure of `m`.
    # Make sure it correctly handles `c => b`, `b => a` in bounds & constraints.
    for col in sort(collect(keys(synonyms)), rev=true)
        representative = variables[synonyms[col]]
        to_remove = variables[col]
        # `to_remove` is unmodified.
        tighten_by(representative, to_remove)

        m[:, representative.id] += m[:, col]
        m[:, col] = 0.0
    end

    # There shouldn't be key conflict.
    for (k, v) in synonyms
        substitutions[k] = LinearExpression(v, length(variables))
    end

    Stats(length(synonyms))
end



end