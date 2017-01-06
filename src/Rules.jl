module Rules

export Statistics, apply_rule, has_updated


function apply_rule end

abstract Statistics{T}

function Base.show(io::IO, x::Statistics)
    s = join(
        "#$name: $(getfield(x, name))" for name in fieldnames(x)
        ", "
    )
    println(io, get_rule(x), "(", s, ")")
end

function get_rule{T}(::Statistics{T})::Symbol
    T.parameters[1]
end

function has_updated(x::Statistics)::Bool
    sum(getfield(x, name) for name in fieldnames(x)) > 0
end

end