using StaticArrays
import Base: @kwdef

const FLOW_SPEC_ETH	 = 0x20
const FLOW_SPEC_IPV4 = 0x30
const FLOW_SPEC_TCP	 = 0x40
const FLOW_SPEC_UDP	 = 0x41

@kwdef struct DeviceAttr
    fw_vers::SVector{64, UInt8} = zeros(SVector{64, UInt8})
    node_guid::UInt64 = 0
    sys_image_guid::UInt64 = 0
    max_mr_size::UInt64 = 0
    page_size_cap::UInt64 = 0
    vendor_id::UInt32 = 0
    vendor_part_id::UInt32 = 0
    hw_ver::UInt32 = 0
    max_qp::Int32 = 0
    max_qp_wr::Int32 = 0
    device_cap_flags::UInt32 = 0
    max_sge::Int32 = 0
    max_sge_rd::Int32 = 0
    max_cq::Int32 = 0
    max_cqe::Int32 = 0
    max_mr::Int32 = 0
    max_pd::Int32 = 0
    max_qp_rd_atom::Int32 = 0
    max_ee_rd_atom::Int32 = 0
    max_res_rd_atom::Int32 = 0
    max_qp_init_rd_atom::Int32 = 0
    max_ee_init_rd_atom::Int32 = 0
    atomic_cap::Int32 = 0
    max_ee::Int32 = 0
    max_rdd::Int32 = 0
    max_mw::Int32 = 0
    max_raw_ipv6_qp::Int32 = 0
    max_raw_ethy_qp::Int32 = 0
    max_mcast_grp::Int32 = 0
    max_mcast_qp_attach::Int32 = 0
    max_total_mcast_qp_attach::Int32 = 0
    max_ah::Int32 = 0
    max_fmr::Int32 = 0
    max_map_per_fmr::Int32 = 0
    max_srq::Int32 = 0
    max_srq_wr::Int32 = 0
    max_srq_sge::Int32 = 0
    max_pkeys::UInt16 = 0
    local_ca_ack_delay::UInt8 = 0
    phys_port_cnt::UInt8 = 0
end # struct DeviceAttr

@kwdef struct SGElement
    addr::UInt64 = 0
    len::UInt32 = 0
    lkey::UInt32 = 0
end

const SGElementOffset1 = fieldtypeoffset(SGElement, 1) # Do we even need the *Offset1 constants???
const SGElementOffset2 = fieldtypeoffset(SGElement, 2)
const SGElementOffset3 = fieldtypeoffset(SGElement, 3)

addr(p::Ptr{SGElement}) = unsafe_load(Ptr{UInt64}(p),SGElementOffset1)
len(p::Ptr{SGElement}) = unsafe_load(Ptr{UInt32}(p),SGElementOffset2)
lkey(p::Ptr{SGElement}) = unsafe_load(Ptr{UInt32}(p),SGElementOffset3)

len!(p::Ptr{SGElement}, n::UInt32) = unsafe_store!(Ptr{UInt32}(p), n, SGElementOffset2)
len!(p::Ptr{SGElement}, n) = len!(p, n % UInt32)

@kwdef struct SendWR
    wr_id::UInt64 = 0
    next::Ptr{SendWR} = 0
    sg_list::Ptr{SGElement} = 0
    num_sge::Int32 = 0
    reserved::SVector{100, UInt8} = zeros(SVector{100, UInt8})
end

const SendWROffset1 = fieldtypeoffset(SendWR, 1) # Do we even need the *Offset1 constants???
const SendWROffset2 = fieldtypeoffset(SendWR, 2)
const SendWROffset3 = fieldtypeoffset(SendWR, 3)
const SendWROffset4 = fieldtypeoffset(SendWR, 4)

wr_id(p::Ptr{SendWR}) = unsafe_load(Ptr{UInt64}(p),SendWROffset1)
next(p::Ptr{SendWR}) = unsafe_load(Ptr{Ptr{SendWR}}(p),SendWROffset2)
sg_list(p::Ptr{SendWR}) = unsafe_load(Ptr{SGElement}(p),SendWROffset3)
num_sge(p::Ptr{SendWR}) = unsafe_load(Ptr{Int32}(p),SendWROffset4)

@kwdef struct RecvWR
    wr_id::UInt64 = 0
    next::Ptr{RecvWR} = 0
    sg_list::Ptr{SGElement} = 0
    num_sge::Int32 = 0
end

const RecvWROffset1 = fieldtypeoffset(RecvWR, 1) # Do we even need the *Offset1 constants???
const RecvWROffset2 = fieldtypeoffset(RecvWR, 2)
const RecvWROffset3 = fieldtypeoffset(RecvWR, 3)
const RecvWROffset4 = fieldtypeoffset(RecvWR, 4)

wr_id(p::Ptr{RecvWR}) = unsafe_load(Ptr{UInt64}(p),RecvWROffset1)
next(p::Ptr{RecvWR}) = unsafe_load(Ptr{Ptr{RecvWR}}(p),RecvWROffset2)
sg_list(p::Ptr{RecvWR}) = unsafe_load(Ptr{SGElement}(p),RecvWROffset3)
num_sge(p::Ptr{RecvWR}) = unsafe_load(Ptr{Int32}(p),RecvWROffset4)
