using ..CryptoGroups.Curves: AffinePoint
using ..CryptoGroups: concretize_type, value
using ..CryptoGroups.Utils: hex2bits, @check

abstract type GroupSpec end

import Base: @kwdef

function point(po::Vector{UInt8}, spec::GroupSpec)

    P = concretize_type(AffinePoint, spec)
    p = P(po)

    return value(p)
end

_parse_bits(x::String, N::Int) = hex2bits(x)[end - N + 1:end]
_parse_bits(x::BitVector, m::Int) = x
_parse_bits(x::Nothing, m::Int) = x


_parse_int(x::String) = parse(BigInt, x, base=16)
_parse_int(x::Integer) = BigInt(x)
_parse_int(::Nothing) = nothing
_parse_int(x::Vector{UInt8}) = octet2int(x)

struct ECP <: GroupSpec
    p::BigInt
    n::Union{BigInt, Nothing} # = nothing
    a::BigInt # = -3
    b::BigInt
    cofactor::Union{Int, Nothing}
    Gx::Union{BigInt, Nothing} # = nothing
    Gy::Union{BigInt, Nothing} # = nothing
    names::Vector{String}

    function ECP(p, n, a, b, cofactor, Gx, Gy; names = String[])

        _a = mod(_parse_int(a), p) # taking mod as conventually a=-3

        _b = _parse_int(b)
        _Gx = _parse_int(Gx)
        _Gy = _parse_int(Gy)
        _n = _parse_int(n)

        return new(p, _n, _a, _b, cofactor, _Gx, _Gy, names)
    end

end

cofactor(curve::ECP) = curve.cofactor

names(curve::ECP) = curve.names

order(curve::ECP) = curve.n
generator(curve::ECP) = (curve.Gx, curve.Gy)

modulus(curve::ECP) = curve.p

bitlength(curve::ECP) = bitlength(modulus(curve))

# I could always add a field for equation to be used

Base.:(==)(x::ECP, y::ECP) = x.p == y.p && x.n == y.n && x.a == y.a && x.b == y.b && x.cofactor == y.cofactor && x.Gx == y.Gx && x.Gy == y.Gy #&& x.names == y.names

a(curve::ECP) = curve.a
b(curve::ECP) = curve.b


abstract type BinaryBasis end

struct PB <: BinaryBasis
    f::Vector{Int}
    PB(f::Vector{Int}) = new(f)
    PB(f::BitVector) = PB(((f.len - 1):-1:0)[f])
end

PB(x::Vector{UInt8}, N::Int) = PB(octet2bits(x, N + 1))

bitlength(x::PB) = maximum(x.f) #- 1

struct GNB <: BinaryBasis
    m::Int
    T::Int

    function GNB(m::Int, T::Int; skip_validation = false)
        if !skip_validation
            @check mod(m, 8) != 0
            gn_basis_exist(m, T) || throw(ArgumentError("Gaussian normal basis for field degree $m does not exist with complexity T = $T"))
        end

        return new(m, T)
    end

    function GNB(m::Int)
        @check mod(m, 8) != 0
        T = gn_basis_representation_rule(m)
        return new(m, T)
    end
end

bitlength(x::GNB) = x.m



struct EC2N{B<:BinaryBasis} <: GroupSpec
    basis::B
    n::Union{BigInt, Nothing}
    a::BitVector
    b::BitVector
    cofactor::Union{Int, Nothing}
    Gx::Union{BitVector, Nothing}
    Gy::Union{BitVector, Nothing}
    names::Vector{String}

    function EC2N(basis::B, n::BigInt, a::BitVector, b::BitVector, cofactor::Union{Int, Nothing}, Gx::BitVector, Gy::BitVector; names=String[]) where B <: BinaryBasis
        bitlength(basis) == length(a) == length(b) == length(Gx) == length(Gy) || throw(ArgumentError("Parameter Input lengths for basis, a, b, Gx, Gy are not equal"))

        new{B}(basis, n, a, b, cofactor, Gx, Gy, names)
    end
    
    function EC2N(basis::B, n::Union{BigInt, Nothing}, a::BitVector, b::BitVector, cofactor::Union{Int, Nothing}; names=String[]) where B <: BinaryBasis
        bitlength(basis) == length(a) == length(b) || throw(ArgumentError("Parameter Input lengths for basis, a, b are not equal"))
        new{B}(basis, n, a, b, cofactor, nothing, nothing, names)
    end

    function EC2N(basis::B, a::BitVector, b::BitVector, cofactor::Union{Int, Nothing}; names=String[]) where B <: BinaryBasis
        bitlength(basis) == length(a) == length(b) || throw(ArgumentError("Parameter Input lengths for basis, a, b are not equal"))
        new{B}(basis, nothing, a, b, cofactor, nothing, nothing, names)
    end
end

names(curve::EC2N) = curve.names

cofactor(curve::EC2N) = curve.cofactor

_parse_bits(x::BitVector, basis::BinaryBasis) = x
_parse_bits(x::String, basis::BinaryBasis) = _parse_bits(x, bitlength(basis))

Base.:(==)(x::E, y::E) where E <: EC2N = x.basis == y.basis && x.n == y.n && x.a == y.a && x.b == y.b && x.cofactor == y.cofactor && x.Gx == y.Gx && x.Gy == y.Gy #&& x.names == y.names

function _int2bits_gnb(x::Int, m::Int)
    if x == 0
        return BitVector(0 for i in 1:m)
    elseif x == 1
        return BitVector(1 for i in 1:m)
    else
        error("Conversion of $x not possible")
    end
end

_parse_bits(x::Int, basis::GNB) = _int2bits_gnb(x, bitlength(basis))

bitlength(x::EC2N) = bitlength(x.basis)


function _int2bits_pb(x::Int, m::Int)
    if x == 0
        return BitVector(0 for i in 1:m)
    elseif x == 1
        return BitVector(((0 for i in 1:m-1)..., 1))
    else
        error("Conversion of $x not possible")
    end
end

_parse_bits(x::Int, basis::PB) = _int2bits_pb(x, bitlength(basis))
_parse_bits(x::Vector{UInt8}, basis::BinaryBasis) = octet2bits(x, bitlength(basis))

# Basis could be nonoptional argument here
function EC2N(basis::BinaryBasis; n=nothing, a, b, cofactor=nothing, G=nothing, Gx=nothing, Gy=nothing, names = String[]) 

    #_n = convert(BigInt, n)
    _n = _parse_int(n)
    _a = _parse_bits(a, basis)
    _b = _parse_bits(b, basis)


    if !isnothing(G)
        sp = EC2N(basis, _a, _b, cofactor; names)
        _Gx, _Gy = point(G, sp) # The method is defined in conversions.jl
    else
        _Gx = _parse_bits(Gx, bitlength(basis))
        _Gy = _parse_bits(Gy, bitlength(basis))
    end


    if isnothing(_Gx) && isnothing(_Gy)
        return EC2N(basis, _n, _a, _b, cofactor; names)
    elseif !isnothing(_Gx) && !isnothing(_Gy)
        return EC2N(basis, _n, _a, _b, cofactor, _Gx, _Gy; names)
    else
        error("Incompatible input.")
    end
end


function EC2N{PB}(; f, kwargs...)
    basis = PB(f)
    return EC2N(basis; kwargs...)
end

function EC2N{GNB}(; m, T, kwargs...)
    basis = GNB(m, T)
    return EC2N(basis; kwargs...)
end

function EC2N(; kwargs...)

    if :f in kwargs
        return EC2N{PB}(kwargs...)
    elseif :m in kwargs && :T in kwargs
        return EC2N{GNB}(kwargs...)
    else
        error("Dispatch can not be infered from passed keyword arguments")
    end
end


order(curve::EC2N) = curve.n
generator(curve::EC2N) = (curve.Gx, curve.Gy)

a(curve::EC2N) = curve.a
b(curve::EC2N) = curve.b


struct Koblitz{B<:BinaryBasis} <: GroupSpec
    bec::EC2N{B}

    function Koblitz{B}(; a, kwargs...) where B <: BinaryBasis

        b = 1

        if a == 0
            cofactor = 4
        elseif a == 1
            cofactor = 2
        else
            error("a can only be 0 or 1.")
        end

        bec =  EC2N{B}(; a, b, cofactor, kwargs...)

        return new{B}(bec)
    end

    function Koblitz(; a, kwargs...)

        b = 1
        #@assert a in [0, 1]

        if a == 0
            cofactor = 4
        elseif a == 1
            cofactor == 2
        else
            error("a can only be 0 or 1.")
        end

        bec =  EC2N(; a, b, cofactor, kwargs...)

        B = typeof(bec.basis)

        return new{B}(bec)
    end
end

names(curve::Koblitz) = names(curve.bec)

cofactor(curve::Koblitz) = cofactor(curve.bec)

order(curve::Koblitz) = order(curve.bec)
generator(curve::Koblitz) = generator(curve.bec)

a(curve::Koblitz) = a(curve.bec)
b(curve::Koblitz) = b(curve.bec)


### MODP spec 

tobint(x::String) = parse(BigInt, x, base=16)
tobint(x::BigInt) = x
tobint(x::Integer) = BigInt(x)
tobint(x::Nothing) = nothing

struct MODP <: GroupSpec
    p::BigInt
    g::Union{BigInt, Nothing}
    q::Union{BigInt, Nothing}
    names::Vector{String}
    
    MODP(p, g, q; names = String[]) = new(tobint(p), tobint(g), tobint(q), names)    
    MODP(p, g; names = String[]) = MODP(p, g, nothing; names)

    MODP(p::Integer; g=nothing, q=nothing, names=String[]) = new(tobint(p), tobint(g), tobint(q), names)
    MODP(p::Integer, g::Integer, q::Integer; names=String[]) = new(tobint(p), tobint(g), tobint(q), names)

    MODP(p::Vector{UInt8}, g::Vector{UInt8}, q::Vector{UInt8}; names=String[]) = new(p |> octet2int, g |> octet2int, q |> octet2int, names)
end

MODP(;p, q, g = nothing, names=String[]) = MODP(p, g, q; names)

Base.:(==)(x::MODP, y::MODP) = x.p == y.p && x.g == y.g && x.q == y.q

names(modp::MODP) = modp.names

generator(spec::MODP) = spec.g
modulus(spec::MODP) = spec.p
order(spec::MODP) = spec.q


name(spec::GroupSpec) = isempty(names(spec)) ? nothing : Symbol(names(spec)[1])


# I could implement a method for a point here

function ECP(; p, n::Union{Integer, Nothing} = nothing, a = -3, b, cofactor = nothing, G=nothing, Gx=nothing, Gy=nothing, names = String[])
    
    if !isnothing(G) 
        ecp = ECP(p, n, a, b, cofactor, nothing, nothing)
        (Gx, Gy) = point(G, ecp) # The only method that depends on the point. 
    end

    return ECP(p, n, a, b, cofactor, Gx, Gy; names)
end
