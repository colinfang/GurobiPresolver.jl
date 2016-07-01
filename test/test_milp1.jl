function test_milp1()
    env = Gurobi.Env()
    original_model = Gurobi.Model(env, "original")
    read_model(original_model, "milp1.mps")

    presolved_model, variable_mapping, constraint_mapping = preprocess(original_model)
end


test_milp1()