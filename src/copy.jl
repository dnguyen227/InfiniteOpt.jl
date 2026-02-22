################################################################################
#                              MODEL COPYING
################################################################################

# Sentinel backend used during deepcopy to avoid the
# GenericModel deepcopy restriction in JuMP.
struct _CopyBackend <: AbstractTransformationBackend end
Base.empty!(::_CopyBackend) = nothing

"""
    InfiniteReferenceMap

Maps variable and constraint references from an original
`InfiniteModel` to their counterparts in a copied model.
Returned by [`JuMP.copy_model(::InfiniteModel)`](@ref).

Supports indexing with `GeneralVariableRef`,
`InfOptConstraintRef`, and expression types.
"""
struct InfiniteReferenceMap
    old_model::InfiniteModel
    new_model::InfiniteModel
end

# Variable ref mapping (preserves indices, swaps model)
function Base.getindex(
    m::InfiniteReferenceMap,
    vref::GeneralVariableRef
)
    return GeneralVariableRef(
        m.new_model,
        _raw_index(vref),
        _index_type(vref),
        _param_index(vref)
    )
end

# Constraint ref mapping
function Base.getindex(
    m::InfiniteReferenceMap,
    cref::InfOptConstraintRef
)
    return InfOptConstraintRef(m.new_model, JuMP.index(cref))
end

# Expression mapping for affine expressions
function Base.getindex(
    m::InfiniteReferenceMap,
    expr::JuMP.GenericAffExpr{T, GeneralVariableRef}
) where {T}
    result = zero(typeof(expr))
    for (coef, var) in JuMP.linear_terms(expr)
        JuMP.add_to_expression!(result, coef, m[var])
    end
    result.constant = expr.constant
    return result
end

# Expression mapping for quadratic expressions
function Base.getindex(
    m::InfiniteReferenceMap,
    expr::JuMP.GenericQuadExpr{T, GeneralVariableRef}
) where {T}
    aff = m[expr.aff]
    terms = OrderedCollections.OrderedDict(
        JuMP.UnorderedPair(m[k.a], m[k.b]) => v
        for (k, v) in expr.terms
    )
    return JuMP.GenericQuadExpr(aff, terms)
end

# Pass-through for scalars
Base.getindex(::InfiniteReferenceMap, x::Number) = x
Base.getindex(::InfiniteReferenceMap, x::AbstractString) = x
Base.getindex(::InfiniteReferenceMap, x::Symbol) = x

# Array mapping
function Base.getindex(
    m::InfiniteReferenceMap,
    val::AbstractArray
)
    return getindex.(m, val)
end

Base.broadcastable(m::InfiniteReferenceMap) = Ref(m)

"""
    JuMP.copy_model(model::InfiniteModel)

Return a copy of `model` and an [`InfiniteReferenceMap`](@ref) that
can be used to obtain the variable and constraint references of the
new model corresponding to references from the original model.

The copied model has a fresh `TranscriptionBackend` and
`ready_to_optimize = false`. An optimizer must be set on the new
model before calling `optimize!`.

## Example
```julia
model = InfiniteModel()
@infinite_parameter(model, t in [0, 1], num_supports = 10)
@variable(model, x, Infinite(t))
@constraint(model, c, x <= 1)

new_model, ref_map = copy_model(model)
new_x = ref_map[x]
new_c = ref_map[c]
```
"""
function JuMP.copy_model(model::InfiniteModel)
    # Swap backend with sentinel to avoid the GenericModel
    # deepcopy restriction in JuMP
    saved_backend = model.backend
    model.backend = _CopyBackend()
    new_model = try
        Base.deepcopy(model)
    finally
        model.backend = saved_backend
    end
    # Give new model a fresh backend
    new_model.backend = TranscriptionBackend()
    new_model.ready_to_optimize = false
    ref_map = InfiniteReferenceMap(model, new_model)
    return new_model, ref_map
end
