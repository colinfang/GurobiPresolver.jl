function test_milp1()
    println("This could take about 2 mins.")
    env = Gurobi.Env()
    original_model = Gurobi.Model(env, "original")
    read_model(original_model, "milp1.mps")

    presolved_model, variable_mapping, constraint_mapping = preprocess(original_model)

    setparams!(original_model, Presolve=-1, LogToConsole=0)
    setparams!(presolved_model, Presolve=0, LogToConsole=0)#, LogFile="presolve_2.log")

    optimize(original_model)
    optimize(presolved_model)

    time_a, time_b, iter_a, iter_b =
        test_model_equivalence(original_model, presolved_model, variable_mapping)

	grb_presolved_model = Gurobi.presolve_model(original_model)

    num_vars_original = num_vars(original_model)
    num_vars_presolved = num_vars(presolved_model)
    num_vars_grb_presolved = num_vars(grb_presolved_model)

    num_consts_original = num_constrs(original_model)
    num_constr_presolved = num_constrs(presolved_model)
    num_constr_grb_presolved = num_constrs(grb_presolved_model)

    println("Original model (#vars=$(num_vars_original), #constrs=$(num_consts_original)) takes $(time_a) sec.")
    println("Gurobi presolved model (#vars=$(num_vars_grb_presolved), #constrs=$(num_constr_grb_presolved)).")
    println("Presolved model (#vars=$(num_vars_presolved), #constrs=$(num_constr_presolved)) takes $(time_b) sec with $(iter_b) iterations.")
end


test_milp1()