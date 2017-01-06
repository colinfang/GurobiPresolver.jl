function test_substitute_fixed_variable()
    m = spzeros(20, 10)
    m[1, 2] = 2
    m[2, 1] = 3
    m[2, 2] = 4
    m[3, 1] = 5

    rhs_s = zeros(20)
    rhs_s[1:3] = 1:3

    variables = [Variable(i, 1.0, 2.0, 'I') for i in 1:10]
    senses = ['=' for _ in 1:20]

    model = DecomposedModel(m, variables, senses, rhs_s)

    println("Before")
    print_constraints(model)
    # 2.0 * x2 = 1.0
    # 3.0 * x1 + 4.0 * x2 = 2.0
    # 5.0 * x1 = 3.0
    variable = Variable(1, 5.0, 5.0, 'I')
    num_zeroed_coefs = GurobiPresolver.VariableFixing.substitute_fixed_variable(m, variable, rhs_s)
    println("After")
    print_constraints(model)
    # 2.0 * x2 = 1.0
    # 4.0 * x2 = -13.0
    @test num_zeroed_coefs == 2
    @test m[1, 1] == 0
    @test m[1, 2] == 2
    @test m[2, 1] == 0
    @test m[2, 2] == 4
    @test m[3, 1] == 0
    @test rhs_s[1] == 1
    @test rhs_s[2] == -13
    @test rhs_s[3] == -22
    @test rhs_s[4] == 0
end

function test_apply_variable_fixing()
    m = spzeros(20, 10)
    m[1, 2] = 2
    m[2, 1] = 3
    m[2, 2] = 4
    m[3, 1] = 5
    rhs_s = zeros(20)
    rhs_s[1:3] = 1:3

    variables = [Variable(i, 1.0, 2.0, 'I') for i in 1:10]
    variables[1].lb = 5
    variables[1].ub = 5

    senses = ['=' for _ in 1:20]

    model = DecomposedModel(m, variables, senses, rhs_s)
    m_info = ModelInfo()

    println("Before")
    print_constraints(model)
    # 2.0 * x2 = 1.0
    # 3.0 * x1 + 4.0 * x2 = 2.0
    # 5.0 * x1 = 3.0
    stats = @time_fun apply_rule(Val{:variable_fixing}, model, m_info)
    println("After")
    print_constraints(model)
    # 2.0 * x2 = 1.0
    # 4.0 * x2 = -13.0
    @test stats.fixed_variables == 1
    @test stats.simplified_terms == 2
    @test m_info.fixed == Set([1])
    @test m[1, 1] == 0
    @test m[1, 2] == 2
    @test m[2, 1] == 0
    @test m[2, 2] == 4
    @test m[3, 1] == 0
    @test rhs_s[1] == 1
    @test rhs_s[2] == -13
    @test rhs_s[3] == -22
    @test rhs_s[4] == 0

end


test_substitute_fixed_variable()
test_apply_variable_fixing()