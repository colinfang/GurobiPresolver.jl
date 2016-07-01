# synonyms is removed => representative
# removed > representative

function apply_synonym_substitution(
        m, senses::Vector{Char}, rhs_s::Vector{Float64},
        lbs::Vector{Float64}, ubs::Vector{Float64}, vtypes::Vector{Char},
        redundant_constraints::Set{Int},
        synonyms::Dict{Int, Int}
    )
    mt = transpose(m)
    mt_nzval = nonzeros(mt)
    mt_rowval = rowvals(mt)
    num_synonyms_pair = 0

    # m is modified
    for row in 1:size(m, 1)
        if !(senses[row] == '=' && rhs_s[row] == 0.0)
            continue
        end

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

        if length(mt_nzrange) != 2
            continue
        end

        coef1, coef2 = mt_nzval[mt_nzrange]
        if coef1 + coef2 != 0.0
            continue
        end

        # Now col1, col2 are synonyms.
        col1, col2 = mt_rowval[mt_nzrange]

        representative = min(col1, col2)
        to_remove = max(col1, col2)

        if haskey(synonyms, to_remove)
            # In 1 pass, it is possible to have x => y, x => z.
            # Because when dealing with x => y, m is modified, but mt is not.
            # In such case we skip till next pass.
            continue
        end

        num_synonyms_pair += 1
        debug(LOGGER, "Detected synonyms pair variable $(to_remove) => $representative from constraint $row.")

        vtype_representative = vtypes[representative]
        if vtypes[to_remove] == 'B' && vtype_representative != 'B'
            vtypes[representative] == 'B'
            info(LOGGER, "Update representative variable $representative vtype $(vtype_representative) => B.")
        elseif vtypes[to_remove] == 'I' && !is_int(vtype_representative)
            vtypes[representative] == 'I'
            info(LOGGER, "Update representative variable $representative vtype $(vtype_representative) => I.")
        end

        m[:, representative] += m[:, to_remove]
        m[:, to_remove] = 0.0
        # So that m[row, :] = 0.0 is not necessary.

        tighten_lb(representative, lbs[to_remove], lbs, vtypes[representative])
        tighten_ub(representative, ubs[to_remove], ubs, vtypes[representative])
        # Note, bounds of to_remove is not changed.
        synonyms[to_remove] = representative
        push!(redundant_constraints, row)
    end

    SynonymSubstitutionStats(num_synonyms_pair)
end


