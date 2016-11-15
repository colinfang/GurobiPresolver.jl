function test_milp1()
    println("This could take about 2 mins.")
    env = Gurobi.Env()
    original_model = Gurobi.Model(env, "original")
    read_model(original_model, "milp1.mps")

    # 0.045381 seconds (244.55 k allocations: 16.644 MB)
    presolved_model, variable_mapping, constraint_mapping, variables = @time_fun preprocess(original_model)

    # Default presolve.
    setparams!(original_model, Presolve=-1, LogToConsole=0)
    # Turn off presolve.
    setparams!(presolved_model, Presolve=0, LogToConsole=0)#, LogFile="presolve_2.log")

    optimize(original_model)
    optimize(presolved_model)

    time_a, time_b, iter_a, iter_b =
        test_model_equivalence(original_model, presolved_model, variable_mapping)

    @time_fun test_variable_fixing(original_model, variable_mapping, variables)
    @time_fun test_synonym_substitution(original_model, variable_mapping)

	grb_presolved_model = Gurobi.presolve_model(original_model)

    num_vars_original = num_vars(original_model)
    num_vars_presolved = num_vars(presolved_model)
    num_vars_grb_presolved = num_vars(grb_presolved_model)

    num_consts_original = num_constrs(original_model)
    num_constr_presolved = num_constrs(presolved_model)
    num_constr_grb_presolved = num_constrs(grb_presolved_model)

    # 40 secs
    println("Original model (#vars=$(num_vars_original), #constrs=$(num_consts_original)) takes $(time_a) sec to find min & max of $(num_vars_presolved) variables.")
    println("Gurobi presolved model (#vars=$(num_vars_grb_presolved), #constrs=$(num_constr_grb_presolved)).")
    # 30 secs
    println("Presolved model (#vars=$(num_vars_presolved), #constrs=$(num_constr_presolved)) takes $(time_b) sec with $(iter_b) iterations to find min & max of $(num_vars_presolved) variables.")
end


test_milp1()