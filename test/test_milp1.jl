function test_milp1()
    println("This could take about 2 mins.")
    model = read_model("milp1.mps")

    print_presolved_model(model)

    # 0.045381 seconds (244.55 k allocations: 16.644 MB)
    presolved = @time_fun preprocess(model)

    # Set MIPGap to 0 in order to perform exact check
    # Default presolve.
    setparams!(model, Threads=1, Presolve=-1, LogToConsole=0, MIPGap=0.0)
    # Turn off presolve.
    setparams!(presolved.model, Threads=1, Presolve=0, LogToConsole=0, MIPGap=0.0)#, LogFile="presolve_2.log")

    clear_obj(model)
    clear_obj(presolved.model)

    # Fill infeasible start to bypass 357 error.
    dummy_start(model)
    dummy_start(presolved.model)
    fixed_variables = [presolved.decomposed.variables[i] for i in presolved.m_info.fixed]
    @time_fun check_fixed_variables(model, fixed_variables)

    undetected_fix = check_model_equivalence(
        model, presolved.model, presolved.variable_mapping
    )


    # @time_fun test_synonym_substitution(original_model, variable_mapping)

    # num_vars_presolved = num_vars(presolved.model)

    # # 40 secs
    # println("Original model takes $(time_a) sec to find min & max of $(num_vars_presolved) variables.")
    # # 30 secs
    # println("Presolved model takes $(time_b) sec with $(iter_b) iterations to find min & max of $(num_vars_presolved) variables.")
    # undetected_fix, variables
end


test_milp1()