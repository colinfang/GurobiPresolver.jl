using GurobiPresolver
using Base.Test

using Gurobi
using Logging

using GurobiPresolver: Variable
#Logging.configure(GurobiPresolver.LOGGER, level=INFO)

include("utils.jl")


"""
Check keys in `variable_mapping` have correct min, max.
"""
function test_model_equivalence(a::Gurobi.Model, b::Gurobi.Model, variable_mapping::Dict{Int, Int})
    # Set MIPGap to 0 in order to perform exact check.
    setparams!(a, LogToConsole=0, Threads=1, MIPGap=0.0)
    setparams!(b, LogToConsole=0, Threads=1, MIPGap=0.0)
    # Reset objcoeffs.
    set_objcoeffs!(a, zeros(num_vars(a)))
    set_objcoeffs!(b, zeros(num_vars(b)))

    time_a = 0.0
    time_b = 0.0
    iter_a = 0
    iter_b = 0

    function t(sense::Symbol, values::Vector{Float64})
        slowest_time = 0.0
        slowest_col = -1

        if sense == :minimize
            Gurobi.set_intattr!(a, "ModelSense", 1)
            Gurobi.set_intattr!(b, "ModelSense", 1)
        elseif sense == :maximize
            Gurobi.set_intattr!(a, "ModelSense", -1)
            Gurobi.set_intattr!(b, "ModelSense", -1)
        else
            error("Sense $sense must be either :minimize or :maximize!")
        end

        for col in 1:num_vars(a)
            if haskey(variable_mapping, col)
                mapped_col = variable_mapping[col]

                Gurobi.set_dblattrelement!(a, "Obj", col, 1.0)
                Gurobi.set_dblattrelement!(b, "Obj", mapped_col, 1.0)

                optimize(a)
                optimize(b)

                obj_a = get_objval(a)
                obj_b = get_objval(b)

                if !isapprox(obj_a, obj_b, rtol=1e-10, atol=1e-10)
                    # TODO: use get_charattrelement.
                    vtype_a = Gurobi.get_charattrarray(a, "VType", 1, num_vars(a))[col]
                    vtype_b = Gurobi.get_charattrarray(b, "VType", 1, num_vars(b))[mapped_col]

                    lb_a = Gurobi.get_dblattrelement(a, "LB", col)
                    ub_a = Gurobi.get_dblattrelement(a, "UB", col)

                    lb_b = Gurobi.get_dblattrelement(b, "LB", mapped_col)
                    ub_b = Gurobi.get_dblattrelement(b, "UB", mapped_col)

                    println("Variable $col ($(vtype_a), [$(lb_a), $(ub_a)]) ~ $(mapped_col) ($(vtype_b), [$(lb_b), $(ub_b)])")
                    error("Different solutions: $(obj_a) != $(obj_b) for $(sense)!")
                end

                time_a += Gurobi.get_runtime(a)
                time_b += Gurobi.get_runtime(b)
                iter_a += Gurobi.get_iter_count(a)
                iter_b += Gurobi.get_iter_count(b)

                run_time = Gurobi.get_runtime(b)
                if run_time > slowest_time
                    slowest_col = mapped_col
                    slowest_time = run_time
                end

                Gurobi.set_dblattrelement!(a, "Obj", col, 0.0)
                Gurobi.set_dblattrelement!(b, "Obj", mapped_col, 0.0)

                values[col] = obj_a
            end
        end
        println("Slowest time for $sense is $(slowest_col) with $(slowest_time) sec.")
    end

    min_values = Array(Float64, num_vars(a))
    max_values = Array(Float64, num_vars(a))

    t(:minimize, min_values)
    t(:maximize, max_values)

    num_fixed = 0
    for col in eachindex(min_values)
        if haskey(variable_mapping, col)
            mapped_col = variable_mapping[col]
            if min_values[col] == max_values[col]
                num_fixed += 1
                if num_fixed < 10
                    println("Variable $col ($(mapped_col)) is actually fixed to $(min_values[col]).")
                end
            end
        end
    end
    println("There are $(num_fixed) more variables fixed that we fail to detect.")

    time_a, time_b, iter_a, iter_b
end


function test_variable_fixing(
        a::Gurobi.Model, variable_mapping::Dict{Int, Int},
        variables::Vector{Variable}
    )
    for x in variables
        if !haskey(variable_mapping, x.id)
            # The variable is fixed.
            Gurobi.set_dblattrelement!(a, "Obj", x.id, 1.0)

            Gurobi.set_intattr!(a, "ModelSense", 1)
            optimize(a)
            v_min = get_objval(a)
            Gurobi.set_intattr!(a, "ModelSense", -1)
            optimize(a)
            v_max = get_objval(a)

            Gurobi.set_dblattrelement!(a, "Obj", x.id, 0.0)

            if !(x.lb == x.ub == v_min == v_max)
                error("$x should be fixed and have true lb = $(v_min), ub = $(v_max)")
            end
        end
    end
end


function test_synonym_substitution(a::Gurobi.Model, variable_mapping::Dict{Int, Int})
    synonyms_by_mapped_col = Dict{Int, Set{Int}}()
    for (x, mapped_col) in variable_mapping
        if haskey(synonyms_by_mapped_col, mapped_col)
            push!(synonyms_by_mapped_col[mapped_col], x)
        else
            synonyms_by_mapped_col[mapped_col] = Set(x)
        end
    end

    # Remove 1 to 1 mapping.
    # The remaining is a list of synonyms.
    for k in collect(keys(synonyms_by_mapped_col))
        if length(synonyms_by_mapped_col[k]) < 2
            delete!(synonyms_by_mapped_col, k)
        end
    end

    for s in values(synonyms_by_mapped_col)
        l = collect(s)
        for i in 1:(length(l) - 1)
            col1 = l[i]
            col2 = l[i + 1]
            # Test col1 - col2 = 0
            Gurobi.set_dblattrelement!(a, "Obj", col1, 1.0)
            Gurobi.set_dblattrelement!(a, "Obj", col2, -1.0)

            Gurobi.set_intattr!(a, "ModelSense", 1)
            optimize(a)
            v_min = get_objval(a)
            Gurobi.set_intattr!(a, "ModelSense", -1)
            optimize(a)
            v_max = get_objval(a)

            Gurobi.set_dblattrelement!(a, "Obj", col1, 0.0)
            Gurobi.set_dblattrelement!(a, "Obj", col2, 0.0)

            if v_min != v_max
                error("Variable $col1 - $col2 should be 0 yet $(v_min) != $(v_max)!")
            end
        end
    end
end

include("test_milp1.jl")
include("test_variable_fixing.jl")
include("test_synonym_substitution.jl")
include("test_variable_bounding.jl")
