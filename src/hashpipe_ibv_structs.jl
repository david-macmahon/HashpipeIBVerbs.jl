using StaticArrays
import Base: @kwdef

fieldtypeoffset(t,i) = fieldoffset(t,i) ÷ Base.datatype_alignment(fieldtype(t,i)) + 1

include("ibverbs_structs.jl")

@kwdef mutable struct SendPkt
    wr::SendWR = SendWR()
    timestamp::UInt64 = 0
end

const SendPktOffset1 = fieldtypeoffset(SendPkt, 1) # Do we even need the *Offset1 constants???
const SendPktOffset2 = fieldtypeoffset(SendPkt, 2)

#wr(p::Ptr{SendPkt}) = unsafe_load(Ptr{SendWR}(p))
timestamp(p::Ptr{SendPkt}) = unsafe_load(Ptr{UInt64}(p), SendPktOffset2)

# These functions take advantage of the fact that a Ptr{SendPkt} is also a
# Ptr{SendWR}.  The `next` function takes advantage of the fact that a SendPkt's
# WR's `next` field points to a SendWR that is also a SendPkt.
wr_id(p::Ptr{SendPkt}) = unsafe_load(Ptr{UInt64}(p),SendWROffset1)
next(p::Ptr{SendPkt}) = unsafe_load(Ptr{Ptr{SendPkt}}(p),SendWROffset2)
sg_list(p::Ptr{SendPkt}) = unsafe_load(Ptr{Ptr{SGElement}}(p),SendWROffset3)
num_sge(p::Ptr{SendPkt}) = unsafe_load(Ptr{Int32}(p),SendWROffset4)

# Provide a convenient way to get/set the length of SendPkt's data
pktlen(p::Ptr{SendPkt}) = sgelen(p|>sg_list)
pktlen!(p::Ptr{SendPkt}, n) = sgelen!(p|>sg_list, n % UInt32)

@kwdef mutable struct RecvPkt
    wr::RecvWR = RecvWR()
    pktlen::UInt32 = 0
    timestamp::UInt64 = 0
end

const RecvPktOffset1 = fieldtypeoffset(RecvPkt, 1) # Do we even need the *Offset1 constants???
const RecvPktOffset2 = fieldtypeoffset(RecvPkt, 2)
const RecvPktOffset3 = fieldtypeoffset(RecvPkt, 3)

#wr(p::Ptr{RecvPkt}) = unsafe_load(Ptr{RecvWR}(p))
pktlen(p::Ptr{RecvPkt}) = unsafe_load(Ptr{UInt32}(p),RecvPktOffset2)
timestamp(p::Ptr{RecvPkt}) = unsafe_load(Ptr{UInt64}(p),RecvPktOffset3)

# These functions take advantage of the fact that a Ptr{RecvPkt} is also a
# Ptr{RecvWR}.  The `next` function takes advantage of the fact that a RecvPkt's
# WR's `next` field points to a RecvWR that is also a RecvPkt.
wr_id(p::Ptr{RecvPkt}) = unsafe_load(Ptr{UInt64}(p),RecvWROffset1)
next(p::Ptr{RecvPkt}) = unsafe_load(Ptr{Ptr{RecvPkt}}(p),RecvWROffset2)
sg_list(p::Ptr{RecvPkt}) = unsafe_load(Ptr{Ptr{SGElement}}(p),RecvWROffset3)
num_sge(p::Ptr{RecvPkt}) = unsafe_load(Ptr{Int32}(p),RecvWROffset4)

@kwdef mutable struct Context
    ctx::Ptr{Cvoid} = 0
    pd::Ptr{Cvoid} = 0
    send_cc::Ptr{Cvoid} = 0
    recv_cc::Ptr{Cvoid} = 0
    send_cq::Ptr{Cvoid} = 0
    recv_cq::Ptr{Cvoid} = 0
    qp::Ptr{Cvoid} = 0
    dev_attr::DeviceAttr = DeviceAttr()
    nqp::UInt32 = 0
    port_num::UInt8 = 0
    mac::SVector{6, UInt8} = zeros(SVector{6,UInt8})
    interface_id::UInt64 = 0
    send_pkt_buf::Ptr{SendPkt} = 0
    recv_pkt_buf::Ptr{RecvPkt} = 0
    send_pkt_head::Ptr{SendPkt} = 0
    send_sge_buf::Ptr{SGElement} = 0
    recv_sge_buf::Ptr{SGElement} = 0
    send_mr_buf::Ptr{UInt8} = 0
    recv_mr_buf::Ptr{UInt8} = 0
    send_mr_size::UInt = 0
    recv_mr_size::UInt = 0
    send_mr::Ptr{Cvoid} = 0
    recv_mr::Ptr{Cvoid} = 0
    send_pkt_num::UInt32 = 0 ###
    recv_pkt_num::UInt32 = 0 ###
    pkt_size_max::UInt32 = 0 ###
    user_managed_flag::Int32 = 0
    max_flows::UInt32 = 16
    ibv_flows::Ptr{Cvoid} = 0
    flow_dst_ips::Ptr{Cvoid} = 0
    mcast_subscriber::Int32 = 0
    interface_name::SVector{16,UInt8} = zeros(SVector{16, UInt8}) ###
end # mutable struct Context
