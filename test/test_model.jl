"""
Check keys in `variable_mapping` have correct min, max.
"""
function check_model_equivalence(a::Gurobi.Model, b::Gurobi.Model, variable_mapping::Dict{Int, Int})
    time_a = 0.0
    time_b = 0.0
    iter_a = 0
    iter_b = 0

    function t(sense::Symbol, values::Vector{Float64})
        slowest_time = 0.0
        slowest_col = -1

        for (col_old, col_new) in variable_mapping
            obj_a, _ = optim(a, col_old, sense)
            obj_b, _ = optim(b, col_new, sense)

            if !isapprox(obj_a, obj_b, rtol=1e-10, atol=1e-10)
                # TODO: use get_charattrelement.
                vtype_a = Gurobi.get_charattrarray(a, "VType", 1, num_vars(a))[col_old]
                vtype_b = Gurobi.get_charattrarray(b, "VType", 1, num_vars(b))[col_new]

                lb_a = Gurobi.get_dblattrelement(a, "LB", col_old)
                ub_a = Gurobi.get_dblattrelement(a, "UB", col_old)

                lb_b = Gurobi.get_dblattrelement(b, "LB", col_new)
                ub_b = Gurobi.get_dblattrelement(b, "UB", col_new)

                println("Variable $(col_old) ($(vtype_a), [$(lb_a), $(ub_a)]) ~ $(col_new) ($(vtype_b), [$(lb_b), $(ub_b)])")
                error("Different solutions: $(obj_a) != $(obj_b) for $(sense)!")
            end

            time_a += Gurobi.get_runtime(a)
            time_b += Gurobi.get_runtime(b)
            iter_a += Gurobi.get_iter_count(a)
            iter_b += Gurobi.get_iter_count(b)

            run_time = Gurobi.get_runtime(b)
            if run_time > slowest_time
                slowest_col = col_new
                slowest_time = run_time
            end

            values[col_old] = obj_a
        end
        println("Slowest time for $sense is $(slowest_col) with $(slowest_time) sec.")
    end

    min_values = Array(Float64, num_vars(a))
    max_values = Array(Float64, num_vars(a))
    t(:min, min_values)
    t(:max, max_values)

    n = length(variable_mapping)
    println("Original model takes $(time_a) sec with $(iter_a) iterations to find min & max of $n variables in variable_mapping.")
    println("Presolved model takes $(time_b) sec with $(iter_b) iterations to find min & max of $n variables in variable_mapping.")

    undetected_fix = Int[];
    for (col_old, col_new) in variable_mapping
        if min_values[col_old] == max_values[col_old]
            push!(undetected_fix, col_old)
            if length(undetected_fix) < 10
                println("Variable $(col_old) ($(col_new)) is actually fixed to $(min_values[col_old]).")
            end
        end
    end
    println("There are $(length(undetected_fix)) more variables fixed that we fail to detect.")

    undetected_fix
end


function check_fixed_variables(
        model::Gurobi.Model,
        fixed_variables::Vector{Variable}
    )
    for x in fixed_variables
        v_max, _ = optim(model, x.id, :max)
        v_min, _ = optim(model, x.id, :min)

        if !(x.lb == x.ub == v_min == v_max)
            error("$x should be fixed and have true lb = $(v_min), ub = $(v_max)")
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