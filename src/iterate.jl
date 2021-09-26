"""
Iterate linked list pointed to by `ptr`, which can be of type `Ptr{SendPkt}`,
`Ptr{RecvPkt}`, `Ptr{SendWR}`, or `Ptr{RecvWR}`.
"""
function Base.iterate(ptr::Ptr{<:Union{SendPkt,RecvPkt,SendWR,RecvWR}}, next_ptr=ptr)
    next_ptr != C_NULL ? (next_ptr, next(next_ptr)) : nothing
end

function Base.eltype(::Ptr{T}) where {T<:Union{SendPkt,RecvPkt,SendWR,RecvWR}}
    T
end

function Base.length(ptr::Ptr{<:Union{SendPkt,RecvPkt,SendWR,RecvWR}})
    n = 0
    for p in ptr
      n += 1
    end
    n
end

function Base.isempty(ptr::Ptr{<:Union{SendPkt,RecvPkt,SendWR,RecvWR}})
  ptr == C_NULL
end
