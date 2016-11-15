"""
- `synonyms` is `to_remove.id => representative.id`.
- `to_remove.id > representative.id`.
"""
function apply_synonym_substitution(
        m, senses::Vector{Char}, rhs_s::Vector{Float64},
        variables::Vector{Variable},
        redundant_constraints::Set{Int},
        synonyms::Dict{Int, Int}
    )::SynonymSubstitutionStats

    synonyms_new = Dict{Int, Int}()

    # `m` is not modified in the following loop.
    for (row, row_element) in enumerate(m, Val{:row})
        if !(senses[row] == '=' && rhs_s[row] == 0.0)
            continue
        end

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

        if coef1 == 0 && coef2 == 0
            push!(redundant_constraints, row)
            continue
        end

        if coef1 + coef2 != 0.0
            continue
        end

        # Now `col1`, `col2` are synonyms.

        representative = variables[min(col1, col2)]
        to_remove = variables[max(col1, col2)]

        if haskey(synonyms_new, to_remove.id)
            # In a pass, it is possible to have `c => x`, `c => y`.
            # In such case we skip till next pass.
            continue
        end

        debug(LOGGER, "Detect synonyms pair $(to_remove) => $representative from constraint $row.")

        synonyms_new[to_remove.id] = representative.id
        push!(redundant_constraints, row)
    end

    # Merge coefs of `to_remove` into `representative`.
    # This would change structure of `m`.
    # Make sure it correctly handles `c => b`, `b => a` in bounds & constraints.
    for col in sort(collect(keys(synonyms_new)), rev=true)
        if haskey(synonyms_new, col)
            representative = variables[synonyms_new[col]]
            to_remove = variables[col]
            # `to_remove` is unmodified.
            tighten_by(representative, to_remove)

            m[:, representative.id] += m[:, col]
            m[:, col] = 0.0
        end
    end

    # Here all `to_remove.id` columns are removed from `m`.
    # There shouldn't be key conflictions.
    merge!(synonyms, synonyms_new)
    SynonymSubstitutionStats(length(synonyms_new))
end


