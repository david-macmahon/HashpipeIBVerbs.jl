import Base: getindex

# Index by `Cptr{c"struct hashpipe_ibv_send_pkt"}`
function Base.getindex(a::AbstractArray, ppkt::Cptr{c"struct hashpipe_ibv_send_pkt"})
    Base.getindex(a, ppkt.wr.wr_id[]+1)
end

# Index by `Cptr{c"struct ibv_send_wr"}`
function Base.getindex(a::AbstractArray, pwr::Cptr{c"struct ibv_send_wr"})
    Base.getindex(a, pwr.wr_id[]+1)
end

# Index by `Cptr{c"struct hashpipe_ibv_recv_pkt"}`
function Base.getindex(a::AbstractArray, ppkt::Cptr{c"struct hashpipe_ibv_recv_pkt"})
    Base.getindex(a, ppkt.wr.wr_id[]+1)
end

# Index by `Cptr{c"struct ibv_recv_wr"}`
function Base.getindex(a::AbstractArray, pwr::Cptr{c"struct ibv_recv_wr"})
    Base.getindex(a, pwr.wr_id[]+1)
end
