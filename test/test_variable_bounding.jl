function test_apply_variable_bounding()
    m = spzeros(20, 10)
    m[1, 1] = 4
    m[1, 2] = -3
    m[1, 3] = -2
    m[1, 4] = 1
    m[1, 5] = 2
    m[2, 1] = -3
    m[2, 2] = 2
    m[2, 3] = -1
    m[2, 4] = 2
    m[2, 5] = 3
    m[3, 6] = 2
    rhs_s = zeros(20)
    rhs_s[1] = 13
    rhs_s[2] = -9
    rhs_s[3] = 2.4

    variables = [Variable(i, 1.0, 2.0, 'C') for i in 1:10]
    variables[1].lb = 0
    variables[1].ub = 1000
    variables[2].lb = 0
    variables[2].ub = 3.2
    variables[3].lb = 1
    variables[3].ub = 5
    variables[4].lb = 2
    variables[4].ub = 4
    variables[5].lb = -0.5
    variables[5].ub = 1000
    senses = ['=' for _ in 1:20]
    senses[1] = '<'
    senses[2] = '<'
    senses[3] = '='

    model = DecomposedModel(m, variables, senses, rhs_s)
    m_info = ModelInfo()

    println("Before")
    print_constraints(model)
    # 4.0 * x1 - 3.0 * x2 - 2.0 * x3 + x4 + 2.0 * x5 < 13.0
    # 3.0 * x1 + 2.0 * x2 - x3 + 2.0 * x4 + 3.0 * x5 < -9.0
    # 2.0 * x6 = 2.4
    stats = @time_fun apply_rule(Val{:variable_bounding}, model, m_info)

    @test stats.row_updates == 3
    @test stats.bounds_updates == 6

    @test 2.1 < variables[1].lb < 2.2
    @test variables[1].ub == 7.9
    @test variables[2].lb == 0
    @test variables[2].ub == 3.2
    @test variables[3].lb == 1
    @test variables[3].ub == 5
    @test variables[4].lb == 2
    @test variables[4].ub == 4
    @test variables[5].lb == -0.5
    @test 5.2 < variables[5].ub < 5.3
    @test variables[6].lb == 1.2
    @test variables[6].ub == 1.2
end


test_apply_variable_bounding()