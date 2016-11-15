module Stats

export VariableBoundingStats, VariableFixingStats
export ConstraintBoundingStats, SynonymSubstitutionStats
export ConstraintSimplificationStats
export PassStats
export has_updated


immutable VariableBoundingStats
    num_row_updates::Int
    num_bounds_updates::Int
end

function Base.show(io::IO, x::VariableBoundingStats)
    print(io, "VariableBoundingStats(#bounds_updates=$(x.num_bounds_updates), #row_updates=$(x.num_row_updates))")
end

has_updated(x::VariableBoundingStats) = x.num_row_updates > 0


immutable VariableFixingStats
    num_fixed_variables::Int
    num_simplified_terms::Int
end

function Base.show(io::IO, x::VariableFixingStats)
    print(io, "VariableFixingStats(#fixed_variables=$(x.num_fixed_variables), #simplified_terms=$(x.num_simplified_terms))")
end

has_updated(x::VariableFixingStats) = x.num_fixed_variables > 0


immutable ConstraintBoundingStats
    num_redundant_constraints::Int
end

function Base.show(io::IO, x::ConstraintBoundingStats)
    print(io, "ConstraintBoundingStats(#redundant_constraints=$(x.num_redundant_constraints))")
end

has_updated(x::ConstraintBoundingStats) = x.num_redundant_constraints > 0


immutable SynonymSubstitutionStats
    num_synonyms_pair::Int
end

function Base.show(io::IO, x::SynonymSubstitutionStats)
    print(io, "SynonymSubstitutionStats(#synonyms_pair=$(x.num_synonyms_pair))")
end

has_updated(x::SynonymSubstitutionStats) = x.num_synonyms_pair > 0


immutable ConstraintSimplificationStats
    num_simplified_constraints::Int
end

function Base.show(io::IO, x::ConstraintSimplificationStats)
    print(io, "ConstraintSimplificationStats(#simplified_constraints=$(x.num_simplified_constraints))")
end


immutable PassStats
    variable_fixing_stats::VariableFixingStats
    synonym_substitution_stats::SynonymSubstitutionStats
    variable_bounding_stats::VariableBoundingStats
    constraint_bounding_stats::ConstraintBoundingStats
    num_effective_variables::Int
    num_effective_constraints::Int
end

function Base.show(io::IO, x::PassStats)
    print(io, "PassStats($(x.variable_fixing_stats), " *
        "$(x.synonym_substitution_stats), " *
        "$(x.variable_bounding_stats), $(x.constraint_bounding_stats), " *
        "#effective_variables=$(x.num_effective_variables), " *
        "#effective_constraints=$(x.num_effective_constraints))")
end




end