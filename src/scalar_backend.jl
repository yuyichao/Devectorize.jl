
type ScalarContext <: CPUContext  # de-vectorized scalar for-loop
end

##########################################################################
#
# 	array access types
#
##########################################################################

# const

type DeConst{T<:Real}
	val::T
end
get{T<:Number}(r::DeConst{T}, i::Integer) = r.val

# vector reader

type DeVecReader{T<:Number}
	src::Vector{T}
end
get{T<:Number}(r::DeVecReader{T}, i::Integer) = r.src[i]


##########################################################################
#
# 	function to generate accessors
#
##########################################################################

devec_reader{T<:Number}(v::T) = DeConst{T}(v)
devec_reader{T<:Number}(a::Vector{T}) = DeVecReader{T}(a)


##########################################################################
#
# 	code generators
#
##########################################################################

function devec_generate_rhs(t::DeNumber, idx::Symbol)
	@gensym rv
	pre = :()
	kernel = :( $(t.val) )
	(pre, kernel)
end

function devec_generate_rhs(t::DeTerminal, idx::Symbol)
	@gensym rd
	pre = :( ($rd) = devec_reader($(t.sym)) )
	kernel = :( get($rd, $idx) )
	(pre, kernel)
end

function devec_generate_rhs{F,
	A1<:AbstractDeExpr}(ex::DeFunExpr{F,(A1,)}, idx::Symbol)
	
	@gensym rd1
	
	a1_pre, a1_kernel = devec_generate_rhs(ex.args[1], idx)
	pre = a1_pre
	kernel = :( ($F)( $a1_kernel ) )
	(pre, kernel)
end

function devec_generate_rhs{F,
	A1<:AbstractDeExpr,
	A2<:AbstractDeExpr}(ex::DeFunExpr{F,(A1,A2)}, idx::Symbol)
	
	@gensym rd1
	
	a1_pre, a1_kernel = devec_generate_rhs(ex.args[1], idx)
	a2_pre, a2_kernel = devec_generate_rhs(ex.args[2], idx)
	pre = :( $a1_pre, $a2_pre )
	kernel = :( ($F)( $a1_kernel, $a2_kernel ) )
	(pre, kernel)
end

function devec_generate_rhs{F,
	A1<:AbstractDeExpr,
	A2<:AbstractDeExpr,
	A3<:AbstractDeExpr}(ex::DeFunExpr{F,(A1,A2,A3)}, idx::Symbol)
	
	@gensym rd1
	
	a1_pre, a1_kernel = devec_generate_rhs(ex.args[1], idx)
	a2_pre, a2_kernel = devec_generate_rhs(ex.args[2], idx)
	a3_pre, a3_kernel = devec_generate_rhs(ex.args[3], idx)
	
	pre = :( $a1_pre, $a2_pre, $a3_pre )
	kernel = :( ($F)( $a1_kernel, $a2_kernel, $a3_kernel ) )
	(pre, kernel)
end


function de_generate(::ScalarContext, assign_ex::Expr)
	@assert assign_ex.head == :(=)
	
	lhs = assign_ex.args[1]
	rhs = de_wrap(assign_ex.args[2])
	
	if isa(rhs, DeFunExpr)
		nargs = length(rhs.args)
		if !is_supported_ewise_fun(fsym(rhs), nargs)
			error("$(fsym(rhs)) with $nargs arguments is not a supported ewise function.")			
		end
	end
	
	@gensym i
	rhs_pre, rhs_kernel = devec_generate_rhs(rhs, i)
	
	quote
		local n = length(($lhs))
		$rhs_pre
		for ($i) = 1 : n
			($lhs)[($i)] = ($rhs_kernel)
		end
	end
end


##########################################################################
#
# 	code-generating macros
#
##########################################################################

macro devec(assign_ex) 
	esc(begin 
		de_generate(ScalarContext(), assign_ex)
	end)
end


