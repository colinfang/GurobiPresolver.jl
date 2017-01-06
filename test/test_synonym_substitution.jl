function test_apply_synonym_substitution()
    m = spzeros(20, 10)
    m[1, 2] = 2
    m[2, 1] = 3
    m[2, 2] = -3
    m[3, 2] = 5
    m[3, 3] = -5
    # Create entry 0 * x1 + 0 * x4
    # Test `x1` & `x4` are not synonyms.
    m[4, 1] = 1
    m[4, 4] = 1
    m[4, 1] = 0
    m[4, 4] = 0
    rhs_s = zeros(20)

    variables = [Variable(i, 1.0, 2.0, 'I') for i in 1:10]
    variables[1].lb = -10
    variables[1].ub = 10
    variables[2].lb = -1
    variables[2].ub = 1
    variables[4].lb = -5
    variables[4].ub = -5
    senses = ['=' for _ in 1:20]

    model = DecomposedModel(m, variables, senses, rhs_s)
    m_info = ModelInfo()

    println("Before")
    print_constraints(model)
    # 2.0 * x2 = 0.0
    # 3.0 * x1 - 3.0 * x2 = 0.0
    # 5.0 * x2 - 5.0 * x3 = 0.0
    stats = @time_fun apply_rule(Val{:synonym_substitution}, model, m_info)
    println("After")
    print_constraints(model)
    # 2.0 * x1 = 0.0
    @test stats.synonyms_pair == 2
    @test sort!(collect(keys(m_info.substitutions))) == [2, 3]
    @test m_info.redundant_constraints == Set(2:3)
    @test variables[1].lb == 1
    @test variables[1].ub == 1

    @test m[1, 1] == 2
    @test m[1, 2] == 0
    @test m[2, 1] == 0
    @test m[2, 2] == 0
    @test m[3, 2] == 0
    @test m[3, 3] == 0
end


test_apply_synonym_substitution()