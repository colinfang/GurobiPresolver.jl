macro time_fun(expr)
    @assert expr.head == :call
    name = string(expr.args[1])
    quote
        println($name, " starts")
        ret = @time $(esc(expr))
        println($name, " ends")
        ret
    end
end

"""
`print_constraints(m, ['=' for i in 1:20], rhs_s)`
"""
function print_constraints(m, sense::Vector{Char}, rhs_s::Vector{Float64})
    for (row, row_element) in enumerate(m, Val{:row})
        terms = ["$coef * x$col" for (col, coef) in enumerate(row_element)]
        if !isempty(terms)
            println(join(terms, " + "), " ", sense[row], " ", rhs_s[row])
        end
    end
end