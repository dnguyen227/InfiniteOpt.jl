@testset "InfiniteReferenceMap" begin
    model = InfiniteModel()
    @infinite_parameter(model, t in [0, 1], num_supports = 10)
    @variable(model, 0 <= x <= 10, Infinite(t))
    @variable(model, y >= 0)

    new_model, ref_map = copy_model(model)

    # Variable ref mapping
    @test ref_map[x] isa GeneralVariableRef
    @test JuMP.owner_model(ref_map[x]) === new_model
    @test JuMP.owner_model(ref_map[y]) === new_model

    # Parameter ref mapping
    @test ref_map[t] isa GeneralVariableRef
    @test JuMP.owner_model(ref_map[t]) === new_model

    # Pass-through for scalars
    @test ref_map[1.0] === 1.0
    @test ref_map["test"] === "test"
    @test ref_map[:sym] === :sym

    # Affine expression mapping
    aff = 2x + 3y + 1
    new_aff = ref_map[aff]
    @test new_aff isa JuMP.GenericAffExpr
    @test JuMP.constant(new_aff) == 1.0

    # Array mapping
    arr = [x, y]
    new_arr = ref_map[arr]
    @test length(new_arr) == 2
    @test JuMP.owner_model(new_arr[1]) === new_model

    # Broadcastable
    @test ref_map isa InfiniteReferenceMap
    @test Ref(ref_map) isa Ref{InfiniteReferenceMap}
end

@testset "copy_model Basic" begin
    model = InfiniteModel()
    @infinite_parameter(model, t in [0, 1], num_supports = 10)
    @variable(model, 0 <= x <= 10, Infinite(t))
    @variable(model, y >= 0)
    @constraint(model, c1, x + y <= 5)
    @objective(model, Min, @integral(x, t) + 2y)

    new_model, ref_map = copy_model(model)

    # Models are independent
    @test new_model !== model
    @test new_model isa InfiniteModel

    # Variable names preserved
    new_x = ref_map[x]
    @test JuMP.name(new_x) == JuMP.name(x)
    new_y = ref_map[y]
    @test JuMP.name(new_y) == JuMP.name(y)

    # Constraint mapping
    new_c1 = ref_map[c1]
    @test JuMP.owner_model(new_c1) === new_model

    # Backend is fresh
    @test !new_model.ready_to_optimize

    # Independence: modify new model, original unchanged
    n_orig = JuMP.num_variables(model)
    @variable(new_model, z)
    @test JuMP.num_variables(new_model) == n_orig + 1
    @test JuMP.num_variables(model) == n_orig

    # Original model is unmodified
    @test model.backend isa TranscriptionBackend
end

@testset "copy_model Derivatives" begin
    model = InfiniteModel()
    @infinite_parameter(model, s in [0, 1], num_supports = 5)
    @variable(model, w, Infinite(s))
    dw = @deriv(w, s)

    new_model, ref_map = copy_model(model)
    new_dw = ref_map[dw]
    @test JuMP.owner_model(new_dw) === new_model
    @test new_dw !== dw
end

@testset "copy_model Measures" begin
    model = InfiniteModel()
    @infinite_parameter(model, u in [0, 1], num_supports = 5)
    @variable(model, v, Infinite(u))
    meas = @integral(v, u)

    new_model, ref_map = copy_model(model)
    @test length(new_model.measures) == length(model.measures)
end

@testset "copy_model Object Dictionary" begin
    model = InfiniteModel()
    @variable(model, q >= 0)

    new_model, ref_map = copy_model(model)
    @test haskey(new_model.obj_dict, :q)
    # obj_dict entries point to new model
    new_q = new_model[:q]
    @test JuMP.owner_model(new_q) === new_model
end

@testset "copy_model Dependent Parameters" begin
    model = InfiniteModel()
    @infinite_parameter(model, p[1:2] in [0, 1],
                        num_supports = 5)
    @variable(model, r, Infinite(p))

    new_model, ref_map = copy_model(model)
    new_r = ref_map[r]
    @test JuMP.owner_model(new_r) === new_model
    for i in 1:2
        new_p = ref_map[p[i]]
        @test JuMP.owner_model(new_p) === new_model
    end
end

@testset "copy_model Base.copy" begin
    model = InfiniteModel()
    @variable(model, a)
    new_model = copy(model)
    @test new_model !== model
    @test new_model isa InfiniteModel
end
