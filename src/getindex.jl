import Base: getindex

# Index by `struct hashpipe_ibv_send_pkt`
function Base.getindex(a::AbstractArray, sendpkt::c"struct hashpipe_ibv_send_pkt")
    Base.getindex(a, sendpkt.wr.wr_id+1)
end

# Index by `struct ibv_send_wr`
function Base.getindex(a::AbstractArray, sendwr::c"struct ibv_send_wr")
    Base.getindex(a, sendwr.wr_id+1)
end

# Index by `struct hashpipe_ibv_recv_pkt`
function Base.getindex(a::AbstractArray, recvpkt::c"struct hashpipe_ibv_recv_pkt")
    Base.getindex(a, recvpkt.wr.wr_id+1)
end

# Index by `struct ibv_recv_wr`
function Base.getindex(a::AbstractArray, recvwr::c"struct ibv_recv_wr")
    Base.getindex(a, recvwr.wr_id+1)
end
