import Base: getindex

"""
    getindex(a::AbstractArray, ptr)

Use the `wr_id` of the object pointed to by `ptr` to index into AbstractArray
`a`.  `ptr` can be of type `Ptr{SendPkt}`, `Ptr{RecvPkt}`, `Ptr{SendWR}`, or
`Ptr{RecvWR}`.  Typically used to index into the `Vector{Vector{UInt8}}`
returned by `wrap_send_bufs` and `wrap_recv_bufs`.
"""
function Base.getindex(a::AbstractArray, ptr::Ptr{<:Union{SendPkt,RecvPkt,SendWR,RecvWR}})
    Base.getindex(a, 1+wr_id(ptr))
end
