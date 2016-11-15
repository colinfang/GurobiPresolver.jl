module IterSparseMatrix

immutable IterCSC{T}
    A::SparseMatrixCSC{T, Int}
    indices::Vector{Int}
    vals::Vector{T}
end

IterCSC{T}(A::SparseMatrixCSC{T, Int}) = IterCSC(A, rowvals(A), nonzeros(A))
Base.eachindex(x::IterCSC) = 1:size(x.A, 2)


immutable Element{T}
    source::IterCSC{T}
    id::Int
    nzrange::UnitRange{Int}
end

Element{T}(source::IterCSC{T}, id::Int) = Element(source, id, nzrange(source.A, id))


function Base.enumerate(A, ::Type{Val{:col}})
    x = IterCSC(A)
    ((i, Element(x, i)) for i in eachindex(x))
end

function Base.enumerate(A, ::Type{Val{:row}})
    At = transpose(A)
    enumerate(At, Val{:col})
end


function Base.enumerate(x::Element)
    ((x.source.indices[i], x.source.vals[i]) for i in x.nzrange)
end

Base.isempty(x::Element) = isempty(x.nzrange)
Base.length(x::Element) = length(x.nzrange)


# A = sparse(reshape(1:4, (2, 2)))

# for (i, element) in enumerate(A, Val{:col})
#     for (j, val) in enumerate(element)
#         println(i, j, val)
#     end
# end

# for (i, element) in enumerate(A, Val{:row})
#     for (j, val) in enumerate(element)
#         println(i, j, val)
#     end
# end

end