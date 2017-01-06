module Variables

export VTYPE_BINARY, VTYPE_INTEGER, VTYPE_CONTINUOUS
export Variable
export is_int, is_fixed, get_variables, from_variables
export tighten_lb, tighten_ub
export tighten_by
export get_max_activity, get_min_activity, SplitBySign

using Gurobi
using MiniLogging
using ..IterSparseMatrix

const LOGGER = get_logger(current_module())

const VTYPE_BINARY = Char(GRB_BINARY)
const VTYPE_INTEGER = Char(GRB_INTEGER)
const VTYPE_CONTINUOUS = Char(GRB_CONTINUOUS)


type Variable
    id::Int
    lb::Float64
    ub::Float64
    vtype::Char

    function Variable(id::Int, lb::Float64, ub::Float64, vtype::Char)
        ret = new(id, lb, ub, vtype)
        check_feasiblility(ret)
        ret
    end
end

"""
- Check immediately after each assignment of `lb` or `ub` (if necessary).
- as well as `Variable` creation.
"""
function check_feasiblility(x::Variable)
    if x.lb > x.ub
        error("$x lb ($(x.lb)) > ub ($(x.ub))")
    end
end


"""
Check if a variable is integer (including binary).
"""
is_int(x::Char) = x == VTYPE_BINARY || x == VTYPE_INTEGER
is_int(x::Variable) = is_int(x.vtype)

function is_fixed(x::Variable)::Bool
    if x.lb == x.ub
        true
    else
        false
    end
end


function get_variables(model::Gurobi.Model)::Vector{Variable}
    lbs = Gurobi.lowerbounds(model)
    ubs = Gurobi.upperbounds(model)
    vtypes = Gurobi.get_charattrarray(model, "VType", 1, num_vars(model))

    [Variable(i, lbs[i], ubs[i], vtypes[i]) for i in eachindex(lbs)]
end

function from_variables(xs::Vector{Variable})
    n = length(xs)
    lbs = Vector{Float64}(n)
    ubs = Vector{Float64}(n)
    vtypes = Vector{Char}(n)
    for (i, x) in enumerate(xs)
        lbs[i] = x.lb
        ubs[i] = x.ub
        vtypes[i] = x.vtype
    end
    lbs, ubs, vtypes
end


"""
Tighten bounds for integers variables.
"""
function tighten_lb(x::Variable)
    if is_int(x)
        v = ceil(x.lb)
        if v > x.lb
            @debug(LOGGER, "Tighten $x lb to integer: $(x.lb) -> $v")
            x.lb = v
            check_feasiblility(x)
        end
    end
end

function tighten_ub(x::Variable)
    if is_int(x)
        v = floor(x.ub)
        if v < x.ub
            @debug(LOGGER, "Tighten $x ub to integer: $(x.ub) -> $v")
            x.ub = v
            check_feasiblility(x)
        end
    end
end


"""
Called by `update_bound...` & `tighten_by` only.
"""
function tighten_ub(x::Variable, v::Float64)::Bool
    if v < x.ub
        @debug(LOGGER, "Tighten $x ub: $(x.ub) -> $v")
        x.ub = v
        check_feasiblility(x)
        tighten_ub(x)
        true
    else
        false
    end
end

function tighten_lb(x::Variable, v::Float64)::Bool
    if v > x.lb
        @debug(LOGGER, "Tighten $x lb: $(x.lb) -> $v")
        x.lb = v
        check_feasiblility(x)
        tighten_lb(x)
        true
    else
        false
    end
end

"""
- Tighten the bounds & `vtype` of `x` from `y`.
- Called by `apply_synonym_substitution` only.
"""
function tighten_by(x::Variable, y::Variable)
    if y.vtype == VTYPE_BINARY && x.vtype != VTYPE_BINARY
        x.vtype = VTYPE_BINARY
        @info(LOGGER, "Tighten $x vtype => B")
    elseif y.vtype == VTYPE_INTEGER && !is_int(x)
        x.vtype = VTYPE_INTEGER
        @info(LOGGER, "Tighten $x vtype => I")
    end
    tighten_lb(x, y.lb)
    tighten_ub(x, y.ub)
end


immutable SplitBySign{T}
    positive::SparseVector{T, Int}
    negative::SparseVector{T, Int}
end


"""
`v[x .< 0] = 0` is very slow.
"""
function SplitBySign{T}(x::SparseVector{T, Int})
    vals = nonzeros(x)
    indices = x.nzind

    positive = copy(x)
    negative = copy(x)

    for i in 1:nnz(x)
        k = indices[i]
        if vals[i] < 0
            positive[k] = 0
        else
            negative[k] = 0
        end
    end

    SplitBySign(positive, negative)
end


# sum empty iterator is an error.

function get_max_activity(
        variables::Vector{Variable}, lhs::SplitBySign
    )::Float64
    reduce(+, 0.0, (coef * variables[i].ub for (i, coef) in nz_terms(lhs.positive))) +
    reduce(+, 0.0, (coef * variables[i].lb for (i, coef) in nz_terms(lhs.negative)))
end

function get_min_activity(
        variables::Vector{Variable}, lhs::SplitBySign
    )::Float64
    reduce(+, 0.0, (coef * variables[i].lb for (i, coef) in nz_terms(lhs.positive))) +
    reduce(+, 0.0, (coef * variables[i].ub for (i, coef) in nz_terms(lhs.negative)))
end

function get_max_activity(
        variables::Vector{Variable}, lhs::SplitBySign, col::Int
    )::Float64
    reduce(+, 0.0, (coef * variables[i].ub for (i, coef) in nz_terms(lhs.positive) if col != i)) +
    reduce(+, 0.0, (coef * variables[i].lb for (i, coef) in nz_terms(lhs.negative) if col != i))
end

function get_min_activity(
        variables::Vector{Variable}, lhs::SplitBySign, col::Int
    )::Float64
    reduce(+, 0.0, (coef * variables[i].lb for (i, coef) in nz_terms(lhs.positive) if col != i)) +
    reduce(+, 0.0, (coef * variables[i].ub for (i, coef) in nz_terms(lhs.negative) if col != i))
end



end