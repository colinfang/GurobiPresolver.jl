using GurobiPresolver
using Base.Test

using Gurobi
using Logging
#Logging.configure(GurobiPresolver.LOGGER, level=INFO)


function get_dblattrelement(model::Gurobi.Model, name::ASCIIString, element::Int)
    a = Array(Float64, 1)
    ret = ccall(
        ("GRBgetdblattrelement", Gurobi.libgurobi), Cint,
        (Ptr{Void}, Ptr{UInt8}, Cint, Ptr{Float64}),
        model, name, element - 1, a
    )
    if ret != 0
        throw(GurobiError(model.env, ret))
    end
    a[1]::Float64
end

function set_dblattrelement!(model::Gurobi.Model, name::ASCIIString, element::Int, v::Real)
    ret = ccall(
        ("GRBsetdblattrelement", Gurobi.libgurobi), Cint,
        (Ptr{Void}, Ptr{UInt8}, Cint, Float64),
        model, name, element - 1, v
    )
    if ret != 0
        throw(GurobiError(model.env, ret))
    end
    nothing
end


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

    function t(sense::Symbol)
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

                set_dblattrelement!(a, "Obj", col, 1.0)
                set_dblattrelement!(b, "Obj", mapped_col, 1.0)

                optimize(a)
                optimize(b)

                obj_a = get_objval(a)
                obj_b = get_objval(b)

                if obj_a != obj_b
                    # TODO: use get_charattrelement.
                    vtype_a = Gurobi.get_charattrarray(a, "VType", 1, num_vars(a))[col]
                    vtype_b = Gurobi.get_charattrarray(b, "VType", 1, num_vars(b))[mapped_col]

                    lb_a = get_dblattrelement(a, "LB", col)
                    ub_a = get_dblattrelement(a, "UB", col)

                    lb_b = get_dblattrelement(b, "LB", mapped_col)
                    ub_b = get_dblattrelement(b, "UB", mapped_col)

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

                set_dblattrelement!(a, "Obj", col, 0.0)
                set_dblattrelement!(b, "Obj", mapped_col, 0.0)
            end
        end
        println("Slowest time for $sense is $(slowest_col) with $(slowest_time) sec.")
    end

    t(:minimize)
    t(:maximize)

    for col in 1:num_vars(a)
        if !haskey(variable_mapping, col)
            # The variable is fixed.
            set_dblattrelement!(a, "Obj", col, 1.0)

            Gurobi.set_intattr!(a, "ModelSense", 1)
            optimize(a)
            v_min = get_objval(a)
            Gurobi.set_intattr!(a, "ModelSense", -1)
            optimize(a)
            v_max = get_objval(a)

            set_dblattrelement!(a, "Obj", col, 0.0)

            if v_min != v_max
                error("Variable $col should be fixed yet $(v_min) != $(v_max)!")
            end
            @test v_min == v_max
        end
    end

    time_a, time_b, iter_a, iter_b
end



include("test_milp1.jl")