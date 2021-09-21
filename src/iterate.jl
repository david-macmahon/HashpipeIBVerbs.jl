import Base: iterate
import Base: IteratorSize

"""
Iterate linked list pointed to by `ptr`, which can be of type `Ptr{SendPkt}`,
`Ptr{RecvPkt}`, `Ptr{SendWR}`, or `Ptr{RecvWR}`.
"""
function Base.iterate(ptr::Ptr{<:Union{SendPkt,RecvPkt,SendWR,RecvWR}}, next_ptr=ptr)
    next_ptr != C_NULL ? (next_ptr, next(next_ptr)) : nothing
end

function Base.IteratorSize(::Ptr{<:Union{SendPkt,RecvPkt,SendWR,RecvWR}})
    Base.SizeUnknown()
end
