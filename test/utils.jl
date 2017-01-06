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

function get_model_info(model::Gurobi.Model)
    string(
        "#num_vars: ", num_vars(model),
        ", #num_constrs: ", num_constrs(model),
        ", #num_nz: ", num_cnzs(model)
    )
end


function optim(model::Gurobi.Model, col::Int, sense::Symbol)
    Gurobi.set_dblattrelement!(model, "Obj", col, 1.0)
    if sense == :max
        Gurobi.set_intattr!(model, "ModelSense", -1)
    elseif sense == :min
        Gurobi.set_intattr!(model, "ModelSense", 1)
    else
        error("Sense $sense must be either :min or :max!")
    end
    optimize(model)
    obj = get_objval(model)
    solution = get_solution(model)
    Gurobi.set_dblattrelement!(model, "Obj", col, 0.0)
    obj, solution
end


function Gurobi.read_model(name::String)
    env = Gurobi.Env()
    model = Gurobi.Model(env, name)
    read_model(model, name)
    model
end

function clear_obj(model::Gurobi.Model)
    set_objcoeffs!(model, zeros(num_vars(model)))
end

function dummy_start(model::Gurobi.Model)
    n = num_vars(model)
    x = fill(1.0, n)
    Gurobi.set_dblattrarray!(model, "Start", 1, n, x)
end