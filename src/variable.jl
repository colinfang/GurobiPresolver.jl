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
is_int(x::Char) = x == 'I' || x == 'B'
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
Tighten bounds by the type.
"""
function tighten_lb(x::Variable)
    if is_int(x)
        v = ceil(x.lb)
        if v > x.lb
            debug(LOGGER, "Tighten $x lb to integer: $(x.lb) -> $v")
            x.lb = v
            check_feasiblility(x)
        end
    end
end

function tighten_ub(x::Variable)
    if is_int(x)
        v = floor(x.ub)
        if v < x.ub
            debug(LOGGER, "Tighten $x ub to integer: $(x.ub) -> $v")
            x.ub = v
            check_feasiblility(x)
        end
    end
end

"""
- Called by `domain_propagation` only.
"""
function tighten_bounds(x::Variable)
    tighten_lb(x)
    tighten_ub(x)
end


"""
Called by `update_bound...` & `tighten_by` only.
"""
function tighten_ub(x::Variable, v::Float64)::Bool
    if v < x.ub
        debug(LOGGER, "Tighten $x ub: $(x.ub) -> $v")
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
        debug(LOGGER, "Tighten $x lb: $(x.lb) -> $v")
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
    if y.vtype == 'B' && x.vtype != 'B'
        x.vtype = 'B'
        info(LOGGER, "Tighten $x vtype => B.")
    elseif y.vtype == 'I' && !is_int(x)
        x.vtype = 'I'
        info(LOGGER, "Tighten $x vtype => I.")
    end
    try
    tighten_lb(x, y.lb)
    tighten_ub(x, y.ub)
    catch
        @show x
        @show y
        rethrow()
    end
end


function tighten_to_lb(x::Variable)
    if x.lb < x.ub
        # Bounds are already integers if variable type is integer.
        debug(LOGGER, "$x is fixed to lb = $(x.lb)")
        x.ub = x.lb
    end
end

function tighten_to_ub(x::Variable)
    if x.lb < x.ub
        # Bounds are already integers if variable type is integer.
        debug(LOGGER, "$x is fixed to ub = $(x.ub)")
        x.lb = x.ub
    end
end