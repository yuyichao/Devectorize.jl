# extensions from other sources

##########################################################################
#
# 	@devec_transform - a code-generating macro for associative types 
#
#	Note: this extension was contributed by Tom Short
#
##########################################################################
#
#   Starting with an associative type `d`, the following assigns or
#   replaces key `a` with the result of `x + y` where `x` or `y` could
#   be keys in `d`.
#
#       @devec_transform d  a = x + y
#
#   This basically converts to the following:
#
#       var1 = has(d, :x) ? d[:x] : x
#       var2 = has(d, :y) ? d[:y] : y
#       @devec res = var1 + var2
#       d[:a] = res
#
#   It contains machinery to convert the symbol to a key type
#   appropriate for the associative type. For example, DataFrames have
#   string keys, so the symbol from the expression needs to be
#   converted to a string. Also of issue is 
#
#   The following forms are supported:
#
#       @devec_transform d  a = x + y  b = x + sum(y)
#
#       @devec_transform(d, a => x + y, b => x + sum(y))
#
# 
##########################################################################


# The following is like Base.has, but converts symbols to appropriate
# key types.
xhas(d, key) = has(d, key)
xhas{K<:String,V}(d::Associative{K,V}, key) = has(d, string(key))

# The appropriate key for the type 
bestkey(d, key) = key
bestkey{K<:String,V}(d::Associative{K,V}, key) = string(key)

#### The following will be needed in package DataFrames for support
#
# 	xhas(d::AbstractDataFrame, key::Symbol) = has(d, string(key))
# 	bestkey(d::AbstractDataFrame, key) = string(key)
# 	bestkey(d::NamedArray, key) = string(key)
#

# This replaces symbols with gensym'd versions and updates
# a lookup dictionary.
replace_syms(x, lookup::Associative) = x

function replace_syms(s::Symbol, lookup::Associative)
    if has(lookup, s)
        lookup[s]
    else
        res = gensym("var")
        lookup[s] = res
        res
    end
end

function replace_syms(e::Expr, lookup::Associative)
    if e.head == :(=>)
        e.head = :(=)
    end
    if e.head == :call
        Expr(e.head, length(e.args) <= 1 ? 
			e.args : 
			[e.args[1], map(x -> replace_syms(x, lookup), e.args[2:end])], e.typ)
    else
        Expr(e.head, isempty(e.args) ? 
			e.args : 
			map(x -> replace_syms(x, lookup), e.args), e.typ)
    end
end

quot(value) = expr(:quote, value)  # Toivo special

function devec_transform_helper(d, args...)
    var_lookup = Dict()
    lhs_lookup = Dict()
    body = Any[]
    for ex in args
        push!(body, compile(ScalarContext(), replace_syms(ex, var_lookup)))
        lhs_lookup[ex.args[1]] = true
    end
    # header
    header = Any[]
    for (s,v) in var_lookup
        push!(header, :($v = DeExpr.xhas(d, DeExpr.bestkey(d, $(quot(s)))) ? 
			d[DeExpr.bestkey(d, $(quot(s)))] : isdefined($(quot(s))) ? $s : nothing))
    end
    # trailer
    trailer = Any[]
    for (s,v) in lhs_lookup
        push!(trailer, :(d[DeExpr.bestkey(d, $(DeExpr.quot(s)))] = $(var_lookup[s])))
    end
    push!(trailer, :(d))
    esc(Expr(:block, [header, body, trailer], Any))
end

macro devec_transform(df, args...)
    devec_transform_helper(df, args...)
end

