module IterSparseMatrix

export nz_terms


function Base.enumerate(A, ::Type{Val{:col}})
    ((i, A[:, i]) for i in 1:size(A, 2))
end

function Base.enumerate(A, ::Type{Val{:row}})
    At = transpose(A)
    enumerate(At, Val{:col})
end


"""
Filter out 0.
"""
function nz_terms{T}(x::SparseVector{T,Int})
    vals = nonzeros(x)
    indices = x.nzind
    ((indices[i], vals[i]) for i in 1:nnz(x) if vals[i] != 0)
end




end