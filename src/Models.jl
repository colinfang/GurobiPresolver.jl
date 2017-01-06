module Models

export DecomposedModel, ModelInfo, LinearExpression
export remove_constraint, stringify_constraint, print_constraints
export log_effective_figures

using MiniLogging
using Parameters
using Gurobi
using ..Variables
using ..IterSparseMatrix

const LOGGER = get_logger(current_module())

"""
Turn `x + y > c` into `-x - y < -c`.
"""
function canonicalize!(m, senses::Vector{Char}, rhs_s::Vector{Float64})
    for (row, row_element) in enumerate(m, Val{:row})
        if senses[row] == '>'
            senses[row] = '<'
            rhs_s[row] = -rhs_s[row]

            for (col, coef) in nz_terms(row_element)
                m[row, col] = -coef
            end
        end
    end
end


immutable DecomposedModel
    m::SparseMatrixCSC{Float64,Int64}
    variables::Vector{Variable}
    senses::Vector{Char}
    rhs_s::Vector{Float64}

    function DecomposedModel(m, variables, senses, rhs_s)
        canonicalize!(m, senses, rhs_s)
        new(m, variables, senses, rhs_s)
    end
end

function DecomposedModel(model::Gurobi.Model)
    if is_qp(model) || is_qcp(model)
        error("Only works with MILP!")
    end
    rhs_s = Gurobi.get_dblattrarray(model, "RHS", 1, num_constrs(model))
    senses = Gurobi.get_charattrarray(model, "Sense", 1, num_constrs(model))
    variables = get_variables(model)
    m = get_constrmatrix(model)

    DecomposedModel(m, variables, senses, rhs_s)
end


type LinearExpression
    c::Float64
    coefs::SparseVector{Float64, Int}
end

"""
- Use equation `lhs = rhs` as source.
- It creates an own copy of `coefs`, so caller may mutate `lhs`.
"""
function LinearExpression(lhs::SparseVector, col::Int, rhs::Float64)
    coef = lhs[col]
    @assert coef != 0
    coefs = -lhs ./ coef
    coefs[col] = 0
    LinearExpression(rhs / coef, coefs)
end

function LinearExpression(col::Int, n::Int)
    coefs = spzeros(n)
    coefs[col] = 1
    LinearExpression(0, coefs)
end

function Base.show(io::IO, x::LinearExpression)
    terms = stringify_constraint(x.coefs)
    if terms == ""
        print(io, x.c)
    else
        if x.c == 0
            print(io, terms)
        else
            print(io, x.c, " + ", terms)
        end
    end
end

"""
- Return one of:
- `:synonym`
- `:antonym`
- `:other`
"""
function categorize(x::LinearExpression)::Symbol
    if x.c != 0
        return :other
    end

    terms = collect(nz_terms(x.coefs))
    if length(terms) != 1
        return :other
    end

    col, coef = terms[1]

    if coef == 1
        return :synonym
    end

    if coef == -1
        return :antonym
    end

    :other
end


immutable ModelInfo
    fixed::Set{Int}
    redundant_constraints::Set{Int}
    # `to_remove => representative`
    substitutions::Dict{Int, LinearExpression}
end

ModelInfo() = ModelInfo(
    Set{Int}(), Set{Int}(), Dict{Int, LinearExpression}()
)

function Base.show(io::IO, x::ModelInfo)
    @unpack fixed, redundant_constraints, substitutions = x

    num_fixed = length(fixed)
    num_redundant_constraints = length(redundant_constraints)

    num_synonyms_pair = 0
    num_antonyms_pair = 0
    num_other_substitution = 0

    for expr in values(x.substitutions)
        x = categorize(expr)
        if x == :synonym
            num_synonyms_pair += 1
        elseif x == :antonym
            num_antonyms_pair += 1
        else
            num_other_substitution += 1
        end
    end

    print(io, """
        ModelInfo(#fixed=$(num_fixed), #redundant_constraints=$(num_redundant_constraints),
            #synonyms=$(num_synonyms_pair), #antonyms=$(num_antonyms_pair), #other_substitutions=$(num_other_substitution))""")
end

"""
- Suppose all keys in `substitutions` can be removed.
- They are all mutually exclusive with `fixed`.
"""
function log_effective_figures(model::DecomposedModel, m_info::ModelInfo)
    @unpack variables, rhs_s = model
    @unpack fixed, redundant_constraints, substitutions = m_info

    num_effective_variables = length(variables) - length(fixed) - length(substitutions)
    num_effective_constraints = length(rhs_s) - length(redundant_constraints)

    @info(LOGGER, "Finally ", m_info)
    @info(LOGGER, "Finally #effected_variables=$(num_effective_variables), #effective_constraints=$(num_effective_constraints).")
end


function remove_constraint(
    m, row::Int, rhs_s::Vector{Float64},
    redundant_constraints::Set{Int}
)
    # It shouldn't modify the structure.
    m[row, :] = 0.0
    rhs_s[row] = 0.0
    @debug(LOGGER, "Removed redundant constraint $row")
    push!(redundant_constraints, row)
end

"""
- `_stringify_constraint(nz_terms(m[row, :]))`
"""
function stringify_constraint(row_element::SparseVector)::String
    terms = String[]
    is_first = true
    for (col, coef) in nz_terms(row_element)
        term =
            if coef == 1
                string(is_first ? "x" : " + x", col)
            elseif coef == -1
                string(is_first ? "-x" : " - x", col)
            elseif coef > 0
                string(is_first ? "" : " + ", coef, " * x", col)
            else
                string(is_first ? "" : " - ", -coef, " * x", col)
            end
        push!(terms, term)
        is_first = false
    end
    join(terms)
end

function stringify_constraint(model::DecomposedModel, row::Int, row_element::SparseVector)
    @unpack senses, rhs_s = model
    terms = stringify_constraint(row_element)
    if terms != ""
        string(terms, " ", senses[row], " ", rhs_s[row])
    else
        ""
    end
end

function stringify_constraint(model::DecomposedModel, row::Int)
    @unpack m, senses, rhs_s = model
    terms = stringify_constraint(m[row, :])
    if terms != ""
        string(terms, " ", senses[row], " ", rhs_s[row])
    else
        ""
    end
end

"""
`print_constraints(m, ['=' for i in 1:20], rhs_s)`
"""
function print_constraints(model::DecomposedModel)
    @unpack m, senses, rhs_s = model
    for (row, row_element) in enumerate(m, Val{:row})
        s = stringify_constraint(model, row, row_element)
        if s != ""
            println(s)
        end
    end
end



end