# Extend Base.copy for new variable types
Base.copy(v::MeasureRef, new_model::InfiniteModel) = MeasureRef(new_model,
                                                                v.index)

"""
    JuMP.name(mref::MeasureRef)::String

Extend [`JuMP.name`](@ref) to return the name associated with a measure
reference.
"""
function JuMP.name(mref::MeasureRef)::String
    return JuMP.owner_model(mref).meas_to_name[mref.index]
end

"""
    JuMP.set_name(mref::MeasureRef, name::String)

Extend [`JuMP.set_name`](@ref) to specify the name of a measure reference.
"""
function JuMP.set_name(mref::MeasureRef, name::String)
    JuMP.owner_model(mref).meas_to_name[JuMP.index(mref)] = name
    return
end

"""
    JuMP.is_valid(model::InfiniteModel, mref::MeasureRef)::Bool

Extend [`JuMP.is_valid`](@ref) to return `Bool` whether `mref` is valid.
"""
function JuMP.is_valid(model::InfiniteModel, mref::MeasureRef)::Bool
    return (model === JuMP.owner_model(mref) && JuMP.index(mref) in keys(model.measures))
end

# Parse the string for displaying a measure
function _make_meas_name(meas::Measure)::String
    return string(meas.data.name, "(", JuMP.function_string(JuMP.REPLMode,
                                                            meas.func), ")")
end

# Used to update the model.var_to_meas and model.param_tomes fields
# this is needed to update measures if variables are deleted
function _update_var_meas_mapping(vrefs::Vector{<:GeneralVariableRef},
                                  mindex::Int)
    for vref in vrefs
        model = JuMP.owner_model(vref)
        if isa(vref, InfOptVariableRef)
            if haskey(model.var_to_meas, JuMP.index(vref))
                push!(model.var_to_meas[JuMP.index(vref)], mindex)
            else
                model.var_to_meas[JuMP.index(vref)] = [mindex]
            end
        elseif isa(vref, ParameterRef)
            if haskey(model.param_to_meas, JuMP.index(vref))
                push!(model.param_to_meas[JuMP.index(vref)], mindex)
            else
                model.param_to_meas[JuMP.index(vref)] = [mindex]
            end
        elseif isa(vref, MeasureRef)
            if haskey(model.meas_to_meas, JuMP.index(vref))
                push!(model.meas_to_meas[JuMP.index(vref)], mindex)
            else
                model.meas_to_meas[JuMP.index(vref)] = [mindex]
            end
        end
    end
    return
end

"""
    add_measure(model::InfiniteModel, meas::Measure)::MeasureRef

Add a measure to `model` and return the corresponding measure reference. This
operates in a manner similar to [`JuMP.add_variable`](@ref).
"""
function add_measure(model::InfiniteModel, meas::Measure)::MeasureRef
    model.next_meas_index += 1
    index = model.next_meas_index
    vrefs = _all_function_variables(meas.func)
    _update_var_meas_mapping(vrefs, index)
    mref = MeasureRef(model, model.next_meas_index)
    model.measures[mref.index] = meas
    JuMP.set_name(mref, _make_meas_name(meas))
    model.meas_in_objective[index] = false
    return mref
end

# Set a default weight function
_w(t) = 1

"""
    DiscreteMeasureData(parameter_ref::ParameterRef,
                        coefficients::Vector{<:Number},
                        supports::Vector{<:Number}; name::String = "measure",
                        weight_function::Function = w(t) = 1)::DiscreteMeasureData

Returns a `DiscreteMeasureData` object that can be utilized to define
measures using [`measure`](@ref). This accepts input for a scalar (single)
parameter. Note that `name` is used for printing purposes and a description of
the other arguments is provided in the documentation for
[`DiscreteMeasureData`](@ref). Errors if supports are out bounds or an unequal
number of supports and coefficients are given.

**Example**
```julia
julia> data = DiscreteMeasureData(pref, [0.5, 0.5], [1, 2], name = "example")
DiscreteMeasureData(pref, [0.5, 0.5], [1, 2], "example", InfiniteOpt._w)
```
"""
function DiscreteMeasureData(parameter_ref::ParameterRef,
                             coefficients::Vector{<:Number},
                             supports::Vector{<:Number};
                             name::String = "measure",
                             weight_function::Function = _w
                             )::DiscreteMeasureData
    return DiscreteMeasureData(parameter_ref, coefficients, supports, name,
                               weight_function)
end

"""
    DiscreteMeasureData(parameter_ref::AbstractArray{<:ParameterRef},
                        coefficients::Vector{<:Number},
                        supports::Vector{<:AbstractArray{<:Number}};
                        name::String = "measure",
                        weight_function::Function = w(t) = 1
                        )::MultiDiscreteMeasureData

Returns a `MultiDiscreteMeasureData` object that can be utilized to
define measures using [`measure`](@ref). This accepts input for an array (multi)
parameter. The inner arrays in the supports vector need to match the formatting
of the array used for `parameter_ref`. Note that `name` is used for printing
purposes and a description of the other arguments is provided in the
documentation for [`MultiDiscreteMeasureData`](@ref). Errors if supports are out
bounds, an unequal number of supports and coefficients are given, the array
formats do not match, or the parameters have different group IDs.

**Example**
```julia
julia> data = DiscreteMeasureData(prefs, [0.5, 0.5], [[1, 1], [2, 2]], name = "example");

julia> typeof(data)
MultiDiscreteMeasureData
"""
function DiscreteMeasureData(parameter_ref::AbstractArray{<:ParameterRef},
                             coefficients::Vector{<:Number},
                             supports::Vector{<:AbstractArray};
                             name::String = "measure",
                             weight_function::Function = _w
                             )::MultiDiscreteMeasureData
    supports = [convert(JuMP.Containers.SparseAxisArray, s) for s in supports]
    parameter_ref = convert(JuMP.Containers.SparseAxisArray, parameter_ref)
    return MultiDiscreteMeasureData(parameter_ref, coefficients, supports, name,
                                    weight_function)
end

"""
    measure_function(mref::MeasureRef)::JuMP.AbstractJuMPScalar

Return the function associated with `mref`.
"""
function measure_function(mref::MeasureRef)::JuMP.AbstractJuMPScalar
    return JuMP.owner_model(mref).measures[JuMP.index(mref)].func
end

"""
    measure_data(mref::MeasureRef)::AbstractMeasureData

Return the measure data associated with `mref`.
"""
function measure_data(mref::MeasureRef)::AbstractMeasureData
    return JuMP.owner_model(mref).measures[JuMP.index(mref)].data
end

# Check a measure function for a particular parameter and return Bool
function _has_parameter(vrefs::Vector{<:GeneralVariableRef},
                        pref::ParameterRef)::Bool
    if _has_variable(vrefs, pref)
        return true
    end
    model = JuMP.owner_model(pref)
    relavent_vindices = model.param_to_vars[JuMP.index(pref)]
    relavent_vrefs = [InfiniteVariableRef(model, vindex) for vindex in relavent_vindices]
    for vref in relavent_vrefs
        if _has_variable(vrefs, vref)
            return true
        end
    end
    return false
end

## Check if expr contains a parameter directly or via an infinite variable
# scalar pref
function _check_has_parameter(expr::JuMP.AbstractJuMPScalar,
                              pref::ParameterRef)
    vrefs = _all_function_variables(expr)
    if !_has_parameter(vrefs, pref)
        error("Measure expression is not parameterized by the parameter " *
              "specified in the measure data.")
    end
    return
end

# array pref
function _check_has_parameter(expr::JuMP.AbstractJuMPScalar,
                              pref::JuMP.Containers.SparseAxisArray{<:ParameterRef})
    vrefs = _all_function_variables(expr)
    for key in keys(pref.data)
        if !_has_parameter(vrefs, pref.data[key])
            error("Measure expression is not parameterized by the parameter " *
                  "specified in the measure data.")
        end
    end
    return
end

# Parse the model pertaining to an expression
function _model_from_expr(expr::JuMP.AbstractJuMPScalar)
    all_vrefs = _all_function_variables(expr)
    if length(all_vrefs) > 0
        return JuMP.owner_model(all_vrefs[1])
    else
        return
    end
end

## Internal functions for adding measure data supports to the parameter supports
# scalar pref
function _add_supports_to_parameters(pref::ParameterRef,
                                     supports::Vector{<:Number})
    add_supports(pref, supports)
    return
end

# array pref
function _add_supports_to_parameters(pref::JuMP.Containers.SparseAxisArray{<:ParameterRef},
                                     supports::Array{<:JuMP.Containers.SparseAxisArray{<:Number}})
    for i = 1:length(supports)
        for key in keys(pref.data)
            add_supports(pref.data[key], supports[i].data[key])
        end
    end
    return
end

"""
    measure(expr::JuMP.AbstractJuMPScalar, data::AbstractMeasureData)::MeasureRef

Return a measure reference that evaluates `expr` using according to `data`. This
is the preferred method for implementing measures which follow the form:
``\\int_{p \\in P} expr(p) w(p) dp`` where ``p`` is an infinite parameter (scalar
or vector) and ``w`` is the weight function. The measure data `data` determines
how the measure is to be evaluated. Typically, the [`DiscreteMeasureData`](@ref)
constructor can be used to for `data`. The variable expression `expr` can contain
`InfiniteOpt` variables, infinite parameters, other measure references (meaning
measures can be nested), and constants. Errors if `expr` does not contain
infinite variables, infinite parameters, or measure references. Also errors if
the measure parameter specified in `data` is not in `expr` and is not in any
the nested measure references. Typically, this is called inside of
[`JuMP.@expression`](@ref), [`JuMP.@objective`](@ref), and
[`JuMP.@constraint`](@ref) in a manner similar to `sum`. Note measures are not
explicitly evaluated until [`build_optimizer_model!`](@ref) is called.

**Example**
```julia
julia> tdata = DiscreteMeasureData(t, [0.5, 0.5], [1, 2], name = "name1");

julia> xdata = DiscreteMeasureData(xs, [0.5, 0.5], [[-1, -1], [1, 1]],
                                   name = "name2");

julia> constr_RHS = @expression(model, measure(g - s + 2, tdata) + s^2)
name1(g(t) - s + 2) + s²

julia> @objective(model, Min, measure(g - 1  + measure(T, xdata), tdata))
name1(g(t) - 1 + name2(T(t, x)))
```
"""
function measure(expr::JuMP.AbstractJuMPScalar,
                 data::AbstractMeasureData)::MeasureRef
    if !isa(expr, Union{InfiniteExpr, MeasureExpr, ParameterExpr})
        error("Expression must contain infinite variables, infinite " *
              "parameters, or measure references")
    end
    model = _model_from_expr(expr)
    if model == nothing
        error("Expression contains no variables.")
    end
    pref = data.parameter_ref
    _check_has_parameter(expr, pref)
    meas = Measure(expr, data)
    _add_supports_to_parameters(pref, data.supports)
    return add_measure(model, meas)
end

"""
    used_by_constraint(mref::MeasureRef)::Bool

Return a `Bool` indicating if `mref` is used by a constraint.

**Example**
```julia
julia> used_by_constraint(mref)
false
```
"""
function used_by_constraint(mref::MeasureRef)::Bool
    return haskey(JuMP.owner_model(mref).meas_to_constrs, JuMP.index(mref))
end

"""
    used_by_measure(mref::MeasureRef)::Bool

Return a `Bool` indicating if `mref` is used by a measure.

**Example**
```julia
julia> used_by_measure(mref)
true
```
"""
function used_by_measure(mref::MeasureRef)::Bool
    return haskey(JuMP.owner_model(mref).meas_to_meas, JuMP.index(mref))
end

"""
    used_by_objective(vmref::MeasureRef)::Bool

Return a `Bool` indicating if `mref` is used by the objective.

**Example**
```julia
julia> used_by_objective(mref)
true
```
"""
function used_by_objective(mref::MeasureRef)::Bool
    return JuMP.owner_model(mref).meas_in_objective[JuMP.index(mref)]
end

"""
    is_used(mref::MeasureRef)::Bool

Return a `Bool` indicating if `mref` is used in the model.

**Example**
```julia
julia> is_used(mref)
true
```
"""
function is_used(mref::MeasureRef)::Bool
    return used_by_measure(mref) || used_by_constraint(mref) || used_by_objective(mref)
end

"""
    JuMP.delete(model::InfiniteModel, mref::MeasureRef)
Extend the `JuMP.delete` function to accomodate measures
"""
function JuMP.delete(model::InfiniteModel, mref::MeasureRef)
    @assert JuMP.is_valid(model, mref) "Invalid measure reference."
    # Reset the transcription status
    if is_used(mref)
        set_optimizer_model_ready(model, false)
    end
    # Remove from dependent measures if there are any
    if used_by_measure(mref)
        for mindex in model.meas_to_meas[JuMP.index(mref)]
            if isa(model.measures[mindex].func, MeasureRef)
                data = model.measures[mindex].data
                model.measures[mindex] = Measure(zero(JuMP.AffExpr), data)
            else
                _remove_variable(model.measures[mindex].func, mref)
            end
            mref2 = MeasureRef(model, mindex)
            JuMP.set_name(mref2, _make_meas_name(model.measures[mindex]))
        end
        delete!(model.meas_to_meas, JuMP.index(mref))
    end
    # Remove from dependent constraints if there are any
    if used_by_constraint(mref)
        for cindex in model.meas_to_constrs[JuMP.index(mref)]
            if isa(model.constrs[cindex].func, MeasureRef)
                set = model.constrs[cindex].set
                model.constrs[cindex] = JuMP.ScalarConstraint(zero(JuMP.AffExpr),
                                                              set)
            else
                _remove_variable(model.constrs[cindex].func, mref)
            end
        end
        delete!(model.meas_to_constrs, JuMP.index(mref))
    end
    # Remove from objective if used there
    if used_by_objective(mref)
        if isa(model.objective_function, MeasureRef)
            model.objective_function = zero(JuMP.AffExpr)
        else
            _remove_variable(model.objective_function, mref)
        end
    end
    # Update that the variable used by it are no longer used by it
    vrefs = _all_function_variables(measure_function(mref))
    for vref in vrefs
        if isa(vref, InfOptVariableRef)
            filter!(e -> e != JuMP.index(mref),
                    model.var_to_meas[JuMP.index(vref)])
            if length(model.var_to_meas[JuMP.index(vref)]) == 0
                delete!(model.var_to_meas, JuMP.index(vref))
            end
        elseif isa(vref, ParameterRef)
            filter!(e -> e != JuMP.index(mref),
                    model.param_to_meas[JuMP.index(vref)])
            if length(model.param_to_meas[JuMP.index(vref)]) == 0
                delete!(model.param_to_meas, JuMP.index(vref))
            end
        elseif isa(vref, MeasureRef)
            filter!(e -> e != JuMP.index(mref),
                    model.meas_to_meas[JuMP.index(vref)])
            if length(model.meas_to_meas[JuMP.index(vref)]) == 0
                delete!(model.meas_to_meas, JuMP.index(vref))
            end
        end
    end
    # delete remaining measure information
    delete!(model.meas_in_objective, JuMP.index(mref))
    delete!(model.measures, JuMP.index(mref))
    delete!(model.meas_to_name, JuMP.index(mref))
    return
end

"""
    JuMP.name(vref::_ReducedInfiniteRef)::String

Extend `JuMP.name` to return name of reduced infinite variable references. This
is used when displaying measure expansions that contain such variables.
"""
function JuMP.name(vref::_ReducedInfiniteRef)::String
    root_name = _root_name(vref.original)
    prefs = parameter_refs(vref.original)
    param_names = _root_names(prefs)
    for (k, v) in vref.supports
        param_names[k] = string(v)
    end
    param_name_tuple = "("
    for i = 1:length(param_names)
        if i != length(param_names)
            param_name_tuple *= string(param_names[i], ", ")
        else
            param_name_tuple *= string(param_names[i])
        end
    end
    param_name_tuple *= ")"
    return string(root_name, param_name_tuple)
end

# Helper function for making place holder point variables
function _make_point_variable(ivref::InfiniteVariableRef)
    inf_model = JuMP.owner_model(ivref)
    index = inf_model.next_var_index += 1
    return PointVariableRef(inf_model, index)
end

## Helper function for making place holder infinite variables
# first time reduction
function _make_reduced_variable(ivref::InfiniteVariableRef, removed_index::Int,
                                support::Union{Number,
                                JuMP.Containers.SparseAxisArray{<:Number}})
    inf_model = JuMP.owner_model(ivref)
    index = inf_model.next_var_index += 1
    return _ReducedInfiniteRef(inf_model, index, ivref,
                               Dict(removed_index => support))
end

# further reduce
function _make_reduced_variable(ivref::InfiniteVariableRef, supports::Dict)
    inf_model = JuMP.owner_model(ivref)
    index = inf_model.next_var_index += 1
    return _ReducedInfiniteRef(inf_model, index, ivref, copy(supports))
end

## Implement functions for expanding measures into regular expressions
# InfiniteVariableRef
function _expand_measure(ivref::InfiniteVariableRef,
                         data::Union{DiscreteMeasureData,
                                     MultiDiscreteMeasureData},
                         trans_model::JuMP.AbstractModel,
                         point_mapper::Function)
    # figure out the parameter groups
    group = group_id(first(data.parameter_ref))
    groups = _groups(parameter_refs(ivref))
    # prepare return AffExpr and get necessary information
    aff = zero(JuMP.GenericAffExpr{Float64, GeneralVariableRef})
    # treat variable as constant if doesn't have measure parameter
    if !(group in groups)
        for i = 1:length(data.supports)
            JuMP.add_to_expression!(aff, data.coefficients[i] *
                                    data.weight_function(data.supports[i]),
                                    ivref)
        end
    # convert variable into point variables if its only parameter is the
    # measure parameter
    elseif length(parameter_refs(ivref)) == 1
        for i = 1:length(data.supports)
            pvref = _make_point_variable(ivref)
            point_mapper(trans_model, pvref, ivref, (data.supports[i],))
            JuMP.add_to_expression!(aff, data.coefficients[i] *
                                    data.weight_function(data.supports[i]),
                                    pvref)
        end
    # make reduced variables if the variable contains other parameters
    else
        tuple_loc = findfirst(isequal(group), groups)
        for i = 1:length(data.supports)
            rvref = _make_reduced_variable(ivref, tuple_loc, data.supports[i])
            JuMP.add_to_expression!(aff, data.coefficients[i] *
                                    data.weight_function(data.supports[i]),
                                    rvref)
        end
    end
    return aff
end

# _ReducedInfiniteRef
function _expand_measure(rvref::_ReducedInfiniteRef,
                         data::Union{DiscreteMeasureData,
                                     MultiDiscreteMeasureData},
                         trans_model::JuMP.AbstractModel,
                         point_mapper::Function)
    # figure out the parameters used by the reduced infinite variable
    orig_prefs = parameter_refs(rvref.original)
    # figure out the parameter groups
    group = group_id(first(data.parameter_ref))
    groups = _groups(parameter_refs(rvref))
    # prepare return AffExpr and get necessary information
    aff = zero(JuMP.GenericAffExpr{Float64, GeneralVariableRef})
    # treat variable as constant if doesn't have measure parameter
    if !(group in groups)
        for i = 1:length(data.supports)
            JuMP.add_to_expression!(aff, data.coefficients[i] *
                                    data.weight_function(data.supports[i]),
                                    rvref)
        end
    # convert variable into point variables if its only parameter is the
    # measure parameter
    elseif length(parameter_refs(rvref)) == 1
        tuple_loc = findfirst(isequal(group), _groups(orig_prefs))
        for i = 1:length(data.supports)
            pvref = _make_point_variable(rvref.original)
            rvref.supports[tuple_loc] = data.supports[i]
            support = Tuple(rvref.supports[j] for j = 1:length(rvref.supports))
            point_mapper(trans_model, pvref, rvref.original, support)
            JuMP.add_to_expression!(aff, data.coefficients[i] *
                                    data.weight_function(data.supports[i]),
                                    pvref)
        end
    # make reduced variables if the variable contains other parameters
    else
        tuple_loc = findfirst(isequal(group), _groups(orig_prefs))
        for i = 1:length(data.supports)
            new_rvref = _make_reduced_variable(rvref.original, rvref.supports)
            new_rvref.supports[tuple_loc] = data.supports[i]
            JuMP.add_to_expression!(aff, data.coefficients[i] *
                                    data.weight_function(data.supports[i]),
                                    new_rvref)
        end
    end
    return aff
end

# FiniteVariableRef
function _expand_measure(vref::FiniteVariableRef,
                         data::Union{DiscreteMeasureData,
                                     MultiDiscreteMeasureData},
                         trans_model::JuMP.AbstractModel,
                         point_mapper::Function)
    aff = zero(JuMP.GenericAffExpr{Float64, GeneralVariableRef})
    # treat the variable as a constant
    for i = 1:length(data.supports)
        JuMP.add_to_expression!(aff, data.coefficients[i] *
                                data.weight_function(data.supports[i]),
                                vref)
    end
    return aff
end

# ParameterRef with scalar data
function _expand_measure(pref::ParameterRef,
                         data::DiscreteMeasureData,
                         trans_model::JuMP.AbstractModel,
                         point_mapper::Function)
    aff = zero(JuMP.GenericAffExpr{Float64, GeneralVariableRef})
    # replace the parameter with its value if it is the measure parameter
    if data.parameter_ref == pref
        for i = 1:length(data.supports)
            JuMP.add_to_expression!(aff, data.coefficients[i] *
                                    data.weight_function(data.supports[i]) *
                                    data.supports[i])
        end
    # treat the parameter as a constant otherwise
    else
        for i = 1:length(data.supports)
            JuMP.add_to_expression!(aff, data.coefficients[i] *
                                    data.weight_function(data.supports[i]),
                                    pref)
        end
    end
    return aff
end

# ParameterRef with vector data
function _expand_measure(pref::ParameterRef,
                         data::MultiDiscreteMeasureData,
                         trans_model::JuMP.AbstractModel,
                         point_mapper::Function)
    aff = zero(JuMP.GenericAffExpr{Float64, GeneralVariableRef})
    # determine if pref is part of the measure parameters
    pref_dict = filter(p -> p[2] == pref, data.parameter_ref.data)
    # replace the parameter with its value if it is the measure parameter
    if length(pref_dict) != 0
        for i = 1:length(data.supports)
            JuMP.add_to_expression!(aff, data.coefficients[i] *
                                    data.weight_function(data.supports[i]) *
                                    data.supports[i][collect(keys(pref_dict))[1]])
        end
    # treat the parameter as a constant otherwise
    else
        for i = 1:length(data.supports)
            JuMP.add_to_expression!(aff, data.coefficients[i] *
                                    data.weight_function(data.supports[i]),
                                    pref)
        end
    end
    return aff
end

# GenericAffExpr
function _expand_measure(expr::JuMP.GenericAffExpr,
                         data::Union{DiscreteMeasureData,
                                     MultiDiscreteMeasureData},
                         trans_model::JuMP.AbstractModel,
                         point_mapper::Function)
    # need to use a quadratic expression in case contains measures with
    # quadratic expressions
    quad = zero(JuMP.GenericQuadExpr{Float64, GeneralVariableRef})
    # expand each variable independently and add all together
    for (var, coef) in expr.terms
        JuMP.add_to_expression!(quad, coef, _expand_measure(var, data,
                                                            trans_model,
                                                            point_mapper))
    end
    # expand over the constant
    if expr.constant != 0
        for i = 1:length(data.supports)
            JuMP.add_to_expression!(quad, data.coefficients[i] *
                                    data.weight_function(data.supports[i]) *
                                    expr.constant)
        end
    end
    # return affexpr if appropriate
    if length(quad.terms) == 0
        return quad.aff
    else
        return quad
    end
end

# GenericQuadExpr
function _expand_measure(expr::JuMP.GenericQuadExpr,
                         data::Union{DiscreteMeasureData,
                                     MultiDiscreteMeasureData},
                         trans_model::JuMP.AbstractModel,
                         point_mapper::Function)
    quad = zero(JuMP.GenericQuadExpr{Float64, GeneralVariableRef})
    # convert the GenericAffExpr
    quad.aff = _expand_measure(expr.aff, data, trans_model, point_mapper)
    for (pair, coef) in expr.terms
        # expand on both variables
        expr_a = _expand_measure(pair.a, data, trans_model, point_mapper)
        expr_b = _expand_measure(pair.b, data, trans_model, point_mapper)
        vars_a = collect(keys(expr_a.terms))
        vars_b = collect(keys(expr_b.terms))
        # combine both variable expressions using the coefficients from one
        # of them
        if length(vars_a) == length(vars_b)
            # are same length therefore have same coefficients
            for i = 1:length(vars_a)
                JuMP.add_to_expression!(quad, coef * expr_a.terms[vars_a[i]],
                                        vars_a[i], vars_b[i])
            end
        elseif length(vars_a) == 1
            # var_a was effectively a constant and var_b was't
            for i = 1:length(vars_b)
                JuMP.add_to_expression!(quad, coef * expr_b.terms[vars_b[i]],
                                        vars_a[1], vars_b[i])
            end
        else
            # var_b was effectively a constant and var_a was't
            for i = 1:length(vars_a)
                JuMP.add_to_expression!(quad, coef * expr_a.terms[vars_a[i]],
                                        vars_a[i], vars_b[1])
            end
        end
    end
    return quad
end

# MeasureRef
function _expand_measure(mref::MeasureRef,
                         data::Union{DiscreteMeasureData,
                                     MultiDiscreteMeasureData},
                         trans_model::JuMP.AbstractModel,
                         point_mapper::Function)
    # determine function and data of the inner measure
    deeper_func = measure_function(mref)
    deeper_data = measure_data(mref)
    # expand the inner measure (note this is recursive for nested measures)
    new_func = _expand_measure(deeper_func, deeper_data, trans_model,
                               point_mapper)
    # expand current level with the inner measure now expanded
    return _expand_measure(new_func, data, trans_model, point_mapper)
end

# Catch all method for undefined behavior
function _expand_measure(expr, data, trans_model::JuMP.AbstractModel,
                         point_mapper::Function)
    expr_type = typeof(expr)
    data_type = typeof(data)
    error("Undefined behavior to expand expression of type $expr_type with " *
          "measure data $data_type. If this functionality is needed consider " *
          "extending `_expand_measure`.")
    return
end

# Map temp point variable references to actual variables by adding a variable to
# the infinite model. This is used by expand(mref) to expand measures within an
# infinite model
function _add_mapped_point_variable(model::InfiniteModel,
                                    pvref::PointVariableRef,
                                    ivref::InfiniteVariableRef, support::Tuple)
    # build variable
    var = JuMP.build_variable(error, _variable_info(ivref), Point,
                              infinite_variable_ref = ivref,
                              parameter_values = support)
    # add the variable completely (note the reference is already made)
    desired_index = JuMP.index(pvref)
    curr_index = model.next_var_index
    model.next_var_index = desired_index - 1
    JuMP.add_variable(model, var)
    model.next_var_index = curr_index
    return
end

"""
    expand(mref::MeasureRef)::JuMP.AbstractJuMPScalar

Return a JuMP scalar function containing the explicit expansion of the measure
`mref`. This expansion is done according to the measure data. Note that
variables are added to the model as necessary to accomodate the expansion (i.e.,
point variables and reduced infinite variables are made as needed). Errors if
expansion is undefined for the measure data and/or the measure expression. If
desired this can be used in combination with [`measure`](@ref) to expand measures
on the fly.

This is useful for extensions that employ a custom optimizer_model since it
can be used evaluate measures before expressions are translated to the new model.
This method can also be extended to handle custom measure data types by extending
[`_expand_measure`] which should be of the form
`_expand_measure(::AbstractJuMPScalar, ::AbstractMeasureData, ::InfiniteModel, point_mapper::Function)`.
See the source code in InfiniteOpt/src/measures.jl for examples of how to do this.

**Example**
```julia
julia> tdata = DiscreteMeasureData(t, [0.5, 0.5], [0, 1])

julia> expr = expand(measure(g + z + T - h - 2, tdata))
0.5 g(0) + 0.5 g(1) + z + 0.5 T(0, x) + 0.5 T(1, x) - h(x) - 2
```
"""
function expand(mref::MeasureRef)::JuMP.AbstractJuMPScalar
    return _expand_measure(measure_function(mref), measure_data(mref),
                           JuMP.owner_model(mref), _add_mapped_point_variable)
end

# TODO add method for expanding all measures in model 
