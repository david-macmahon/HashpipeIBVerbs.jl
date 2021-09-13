module HashpipeIBVerbs

export @mac_str

module Impl

  using CBinding

  let
    c`-lhashpipe_ibverbs`
  end

  c"uint8_t" = UInt8
  c"uint16_t" = UInt16
  c"uint32_t" = UInt32
  c"uint64_t" = UInt64
  c"size_t" = Int

  c"""
    #include "infiniband/verbs.h"
    #include "hashpipe_ibverbs.h"
  """

end # module Impl

using CBinding
using .Impl

const IBV_FLOW_SPEC_ETH  = c"IBV_FLOW_SPEC_ETH"
const IBV_FLOW_SPEC_IPV4 = c"IBV_FLOW_SPEC_IPV4"
const IBV_FLOW_SPEC_TCP  = c"IBV_FLOW_SPEC_TCP"
const IBV_FLOW_SPEC_UDP  = c"IBV_FLOW_SPEC_UDP"

include("getindex.jl")
include("iterate.jl")

"""
    mac(s) -> NTuple{6, UInt8}
    mac("11:22:33:44:55:66") -> (0x11, 0x22, 0x33, 0x44, 0x55, 0x66)

Parses `s` as a colon delimited hexadecimal MAC address and returns an
`NTuple{6,UInt8}`.
"""
function mac(s)::NTuple{6, UInt8}
  octets = split(s,':')
  length(octets) == 6 || error("malformed mac $s")
  tuple(map(o->parse(UInt8, o, base=16), octets)...)
end

"""
    @mac_str -> NTuple{6, UInt8}
    mac("11:22:33:44:55:66") -> (0x11, 0x22, 0x33, 0x44, 0x55, 0x66)

Parses a `String` literal as a colon delimited hexadecimal MAC address and
returns an `NTuple{6,UInt8}`.
"""
macro mac_str(s)
  mac(s)
end

"""
Create and initialize a `struct hashpipe_ibv_context`.  Returns a pointer to the
structure.  The returned pointer can be passed to other functions in this
module.
"""
function init(interface_name, send_pkt_num, recv_pkt_num, pkt_size_max, max_flows=16)
  ctx=c"struct hashpipe_ibv_context"(
    interface_name=interface_name,
    send_pkt_num=send_pkt_num,
    recv_pkt_num=recv_pkt_num,
    pkt_size_max=pkt_size_max,
    max_flows=max_flows
    )

  pctx = Libc.malloc(ctx)

  c"hashpipe_ibv_init"(pctx) == 0 || error(Libc.strerror())

  pctx
end

"""
Release all library managed resources and frees all library managed memory
associated with `pctx`, which should be a pointer returned by `init`.
"""
function shutdown(pctx)
  c"hashpipe_ibv_shutdown"(pctx) == 0 || error(Libc.strerror())
end

"""
    flow(pctx, flow_idx, flow_type,
         dst_mac, src_mac, ether_type, vlan_tag,
         src_ip, dst_ip, src_port, dst_port)

`flow` is used to setup flow rules on the NIC to select which incoming packets
will be passed to us by the NIC.  Flows are specified by providing values that
various fields in the packet headers must match.  Fields that can be matched
exist at the Ethernet level, the IPv4 level, and the TCP/UDP level.  The fields
available for matching are:

  - dst_mac    Ethernet destination MAC address (NTuple{6,UInt8},Carray,Nothing)
  - src_mac    Ethernet source MAC address      (NTuple{6,UInt8},Carray,Nothing)
  - ether_type Ethernet type field              (UInt16)
  - vlan_tag   Ethernet VLAN tag                (UInt16)
  - src_ip     IP source address                (UInt32)
  - dst_ip     IP destination address           (UInt32)
  - src_port   TCP/UDP source port              (UInt16)
  - dst_port   TCP/UDP destination port         (UInt16)

The `flow_idx` parameter specifies which flow rule to assign this flow to and
must be between `1` and `max_flows` (inclusive).  The user specifies `max_flows`
when initializing the `hashpipe_ibv_context` structure and `flow_idx` must be
less than that number.  If a flow already exists at the index `flow_idx`, that
flow is destroyed before the new flow is created and stored at the same index.

The `flow_type` field specifies the type pf the flow.  Supported values are:

  - `IBV_FLOW_SPEC_ETH` This matches packets only at the Ethernet layer.  Match
                        fields for IP/TCP/UDP are ignored.

  - `IBV_FLOW_SPEC_IPV4` This matches at the Ethernet and IPv4 layers.  Match
                         fields for TCP/UDP are ignored.  Flow rules at this
                         level include an implicit match on the Ethertype field
                         (08 00) to select only IP packets.

  - `IBV_FLOW_SPEC_TCP`,`IBV_FLOW_SPEC_UDP` These match at the Ethernet, IPv4,
                                            and TCP/UDP layers.  Flow rules of
                                            these types include an implicit
                                            match on the Ethertype field to
                                            select only IP packets and the IP
                                            protocol field to select only TCP or
                                            UDP packets.

Not all fields need to be matched.  For fields for which a match is not desired,
simply pass `nothing` for MAC addess fields or `0` for the other fields and that
field will be excluded from the matching process.  This means that it is not
possible to match against zero valued fields except for the bizarre case of a
zero valued MAC address.  In practice this is unlikely to be a problem.

Passing `nothing`/`0` for all the match fields will result in the destruction of
any flow at the `flow_idx` location, but no new flow will be stored there.

The `src_mac` and `dst_mac` values  must be in network byte order.  The
recommended type for passing MAC addresses is `NTuple{6,UInt8}`.  String literal
MAC addresses can be converted to that type by the `@mac_str` macro (e.g.
`mac"11:22:33:44:55:66`).  String variables containing MAC addresses can be
converted using the `mac` function.  Note that the `mac` field of `pctx` will
contain the MAC address of the NIC port being used and can be passed directly as
`pctx[].mac`.

Some NICs may require a `dst_mac` match in order to enable any packet reception
at all.  This can be the unicast MAC address of the NIC port or a multicast
Ethernet MAC address for receiving multicast packets.  If a multicast `dst_ip`
is given, `dst_mac` will be ignored and the multicast MAC address corresponding
to `dst_ip` will be used.

The non-MAC parameters are passed as values and must be in host byte order.
"""
function flow(pctx, flow_idx, flow_type,
              dst_mac, src_mac, ether_type, vlan_tag,
              src_ip, dst_ip, src_port, dst_port)
  c"hashpipe_ibv_flow"(pctx, flow_idx-1, flow_type,
    dst_mac === nothing ? C_NULL : Ref(dst_mac),
    src_mac === nothing ? C_NULL : Ref(src_mac),
    ether_type, vlan_tag,
    src_ip, dst_ip,
    src_port, dst_port
  ) == 0 || error(Libc.errno())

  nothing
end

function recv_pkts(pctx, timeout=-1)
  pkts = c"hashpipe_ibv_recv_pkts"(pctx, timeout)
  pkts == C_NULL ? nothing : pkts
end

function release_pkts(pctx, recv_pkt)
  c"hashpipe_ibv_release_pkts"(pctx, recv_pkt) == 0 || error(Libc.strerror())
  nothing
end

function get_pkts(pctx, num_pkts=1)
  Libc.errno(0)
  pkts = c"hashpipe_ibv_get_pkts"(pctx, num_pkts)
  if pkts == C_NULL && Libc.errno() != 0
    error(Libc.strerror())
  end
  pkts == C_NULL ? nothing : pkts
end

function send_pkts(pctx, send_pkt)
  # Always use QP 0 (since multi-QP support may be disappearing)
  c"hashpipe_ibv_send_pkts"(pctx, send_pkt, 0) == 0 || error(Libc.strerrno())
  nothing
end

"""
Wrap the send packet buffers of `pctx` with `Vector{UInt8}`.  Return
`Vector{Vector{UInt8}}`.
"""
function wrap_send_bufs(pctx)
  recv_bufs = Vector{Vector{UInt8}}()
  wr = pctx[].recv_pkt_buf[1].wr
  for i in 1:pctx[].recv_pkt_num
    # TODO Support mutiple scatter/gather elements per work request
    @assert wr.wr_id == i-1 "Expected wr_id $(i-1), got $(wr.wr_id)"
    push!(recv_bufs, unsafe_wrap(Array, Ptr{UInt8}(wr.sg_list[1].addr), wr.sg_list[1].length))
    wr.next != C_NULL && (wr = wr.next[])
  end
  recv_bufs
end

"""
Wrap the receive packet buffers of `pctx` with `Vector{UInt8}`.  Return
`Vector{Vector{UInt8}}`.
"""
function wrap_recv_bufs(pctx)
  recv_bufs = Vector{Vector{UInt8}}()
  wr = pctx[].recv_pkt_buf[1].wr
  for i in 1:pctx[].recv_pkt_num
    # TODO Support mutiple scatter/gather elements per work request
    @assert wr.wr_id == i-1 "Expected wr_id $(i-1), got $(wr.wr_id)"
    push!(recv_bufs, unsafe_wrap(Array, Ptr{UInt8}(wr.sg_list[1].addr), wr.sg_list[1].length))
    wr.next != C_NULL && (wr = wr.next[])
  end
  recv_bufs
end

end # module HashpipeIBVerbs
