module HashpipeIBVerbs

export mac
export @mac_str

export wr_id
export next
export sg_list
export num_sge
export timestamp
export pktlen
export pktlen!
export lkey

export foreach_send_pkt
export foreach_recv_pkt

export wrap_send_bufs
export wrap_recv_bufs

include("hashpipe_ibv_structs.jl")
include("iterate.jl")
include("getindex.jl")

"""
    mac(m) -> SVector{6, UInt8}
    mac("11:22:33:44:55:66") -> (0x11, 0x22, 0x33, 0x44, 0x55, 0x66)
    mac(0x112233445566") -> (0x11, 0x22, 0x33, 0x44, 0x55, 0x66)

Parse `m::AbstractString` as a colon delimited hexadecimal MAC address or the
lower 6 bytes of `m::UInt64` as a MAC address and return an `SVector{6, UInt8}`.
An `identity`-like method also exists for an `SVector{6, UInt8}` input type so
calling `mac` on a MAC address compatible `SVector{6, UInt8}` (e.g. the output
of a previous `mac` call) is allowed.
"""
function mac(m::AbstractString)::SVector{6, UInt8}
    octets = split(m,':')
    length(octets) == 6 || error("malformed mac ", s)
    SVector{6,UInt8}(map(o->parse(UInt8, o, base=16), octets))
end

function mac(m::UInt64)::SVector{6, UInt8}
    SVector{6,UInt8}(
        UInt8((m>>40) & 0xff), UInt8((m>>32) & 0xff), UInt8((m>>24) & 0xff),
        UInt8((m>>16) & 0xff), UInt8((m>> 8) & 0xff), UInt8( m      & 0xff)
    )
end

# mac of a MAC compatible SVector is simply itself
function mac(m::SVector{6, UInt8})
    m
end

"""
    @mac_str -> SVector{6, UInt8}
    mac("11:22:33:44:55:66") -> (0x11, 0x22, 0x33, 0x44, 0x55, 0x66)

Parses a `String` literal as a colon delimited hexadecimal MAC address and
returns an `SVector{6,UInt8}`.
"""
macro mac_str(s)
    mac(s)
end

const hashpipe_ibv_init = Ref{Ptr{Cvoid}}()
const hashpipe_ibv_shutdown = Ref{Ptr{Cvoid}}()
const hashpipe_ibv_flow = Ref{Ptr{Cvoid}}()
const hashpipe_ibv_recv_pkts = Ref{Ptr{Cvoid}}()
const hashpipe_ibv_release_pkts = Ref{Ptr{Cvoid}}()
const hashpipe_ibv_get_pkts = Ref{Ptr{Cvoid}}()
const hashpipe_ibv_send_pkts = Ref{Ptr{Cvoid}}()

function __init__()
    lib = Libc.dlopen("libhashpipe_ibverbs")
    hashpipe_ibv_init[] = Libc.dlsym(lib, "hashpipe_ibv_init")
    hashpipe_ibv_shutdown[] = Libc.dlsym(lib, "hashpipe_ibv_shutdown")
    hashpipe_ibv_flow[] = Libc.dlsym(lib, "hashpipe_ibv_flow")
    hashpipe_ibv_recv_pkts[] = Libc.dlsym(lib, "hashpipe_ibv_recv_pkts")
    hashpipe_ibv_release_pkts[] = Libc.dlsym(lib, "hashpipe_ibv_release_pkts")
    hashpipe_ibv_get_pkts[] = Libc.dlsym(lib, "hashpipe_ibv_get_pkts")
    hashpipe_ibv_send_pkts[] = Libc.dlsym(lib, "hashpipe_ibv_send_pkts")
end

"""
    init(interface_name, send_pkt_num, recv_pkt_num, pkt_size_max[, max_flows])::Context

Create and initialize a `Context`.  structure.  The returned `Context` can be
passed to other functions in this module.

  - `interface_name` is the name of the local network interface to use (e.g. `"eth4"`)
  - `send_pkt_num` is the number of `SendPkt`s to allocate
  - `recv_pkt_num` is the number of `RecvPkt`s to allocate
  - `pkt_size_max` is the size of each packet buffer (sets the max packet size)
  - `max_flows` is the number of flow rules to support (defaults to 16 if omitted)
"""
function init(interface_name, send_pkt_num, recv_pkt_num, pkt_size_max, max_flows=16)
    iface_bytes = vcat(codeunits(interface_name), zeros(UInt8, 16))
    ctx=Context(
        interface_name=SVector{16, UInt8}(iface_bytes[1:16]),
        send_pkt_num=send_pkt_num,
        recv_pkt_num=recv_pkt_num,
        pkt_size_max=pkt_size_max,
        max_flows=max_flows
    )

    rc = @ccall $(hashpipe_ibv_init[])(Ref(ctx)::Ptr{Context})::Cint
    rc == 0 ? ctx : error(Libc.strerror())
end

"""
    shutdown(ctx::Context)::Nothing

Release all library managed resources and frees all library managed memory
associated with `pctx`, which should be a pointer returned by `init`.
"""
function shutdown(ctx)
    rc = @ccall $(hashpipe_ibv_shutdown[])(Ref(ctx)::Ptr{Context})::Cint
    rc == 0 ? nothing : error(Libc.strerror())
end

"""
    flow(ctx, flow_idx; flow_type,
         dst_mac, src_mac, ether_type, vlan_tag,
         src_ip, dst_ip, src_port, dst_port)::Nothing

`flow` is used to setup flow rules on the NIC to select which incoming packets
will be passed to us by the NIC.  Flows are specified by providing values that
various fields in the packet headers must match.  Fields that can be matched
exist at the Ethernet level, the IPv4 level, and the TCP/UDP level.  The fields
available for matching are:

  - dst_mac    Ethernet destination MAC address (SVector{6,UInt8},String,Nothing)
  - src_mac    Ethernet source MAC address      (SVector{6,UInt8},String,Nothing)
  - ether_type Ethernet type field              (UInt16)
  - vlan_tag   Ethernet VLAN tag                (UInt16)
  - src_ip     IP source address                (UInt32)
  - dst_ip     IP destination address           (UInt32)
  - src_port   TCP/UDP source port              (UInt16)
  - dst_port   TCP/UDP destination port         (UInt16)

The `flow_idx` parameter specifies which flow rule to assign this flow to and
must be between `1` and `ctx.max_flows` (inclusive).  If a flow already exists
at the index `flow_idx`, that flow is destroyed before the new flow is created
and stored at the same index.

The `flow_type` field specifies the type pf the flow.  Supported values are:

  - `FLOW_SPEC_ETH` This matches packets only at the Ethernet layer.  Match
                    fields for IP/TCP/UDP are ignored.

  - `FLOW_SPEC_IPV4` This matches at the Ethernet and IPv4 layers.  Match
                     fields for TCP/UDP are ignored.  Flow rules at this
                     level include an implicit match on the Ethertype field
                     (08 00) to select only IP packets.

  - `FLOW_SPEC_TCP`,`FLOW_SPEC_UDP` These match at the Ethernet, IPv4, and
                                    TCP/UDP layers.  Flow rules of these types
                                    include an implicit match on the Ethertype
                                    field to select only IP packets and the IP
                                    protocol field to select only TCP or UDP
                                    packets.

Not all fields need to be matched.  For fields for which a match is not desired,
simply do not specify their keywords or pass `nothing` for the MAC addess fields
or `0` for the other fields to exclude those fields from the matching process.
This means that it is not possible to match against zero valued fields except
for the bizarre case of a zero valued MAC address.  In practice this is unlikely
to be a problem.

`flow_type` defaults to `FLOW_SPEC_UDP`, but if `src_port` and `dst_port` are
both zero, then `flow_type` will be automatically determined based on which
other parameters are non-zero/nothing.  Thus `flow_type` only needs to be
specified explicitly if it is `FLOW_SPEC_TCP`.

Passing no keyward arguments (or `nothing`/`0` for all keyword arguments) will
result in the destruction of any flow at the `flow_idx` location, but no new
flow will be stored there.

The `src_mac` and `dst_mac` values  must be in network byte order.  The
recommended type for passing MAC addresses is `SVector{6,UInt8}`.  String
literal MAC addresses can be converted to that type by the `@mac_str` macro
(e.g.  `mac"11:22:33:44:55:66`).  `String` or `UInt64` values passed as MAC
addresses will be converted using the `mac` function.  Note that the `mac` field
of `ctx` will contain the MAC address of the NIC port being used and can be
passed as `dst_mac`.

Some NICs may require a `dst_mac` match in order to enable any packet reception
at all.  This can be the unicast MAC address of the NIC port or a multicast
Ethernet MAC address for receiving multicast packets.  If a multicast `dst_ip`
is given, `dst_mac` will be ignored and the multicast MAC address corresponding
to `dst_ip` will be used.

The non-MAC parameters are passed as values and must be in host byte order.  The
`src_ip` and `dst_ip` arguments may be passed as `UInt32` values or `IPv4`
opjects (e.g. `ip"192.168.0.1"`).
"""
function flow(ctx, flow_idx; flow_type=FLOW_SPEC_UDP,
              dst_mac=nothing, src_mac=nothing, ether_type=0, vlan_tag=0,
              src_ip=0, dst_ip=0, src_port=0, dst_port=0)

    if src_port == 0 && dst_port == 0
        flow_type = (src_ip == 0 && dst_ip == 0) ? FLOW_SPEC_ETH : FLOW_SPEC_IPV4
    end

    rc = @ccall $(hashpipe_ibv_flow[])(
                  Ref(ctx)::Ptr{Context},
                  (flow_idx-1)::UInt32, flow_type::Cint,
                  (dst_mac === nothing ? C_NULL : Ref(mac(dst_mac)))::Ptr{Cvoid},
                  (src_mac === nothing ? C_NULL : Ref(mac(src_mac)))::Ptr{Cvoid},
                  ether_type::UInt16, vlan_tag::UInt16,
                  UInt32(src_ip)::UInt32, UInt32(dst_ip)::UInt32,
                  src_port::UInt16, dst_port::UInt16
                 )::Cint

    rc == 0 ? nothing : error(Libc.strerror())
end

"""
    recv_pkts(ctx::Context)::Ptr{RecvPkt}
    recv_pkts(ctx::Context, timeout_ms::Integer)::Ptr{RecvPkt}

Return a `Ptr{RecvPkt}` that points to a linked list of `RecvPkt` objects with
received packets if any, otherwise it will return `Ptr{RecvPkt}(0)`.  If no
received packets are already queued, it will wait no longer than `timeout_ms`
milliseconds for packets to arrive.   A timeout of zero returns immediately.  A
negative timeout waits "forever" (the default if `timeout_ms` is omitted).

Because notifications from the underlying library are asynchronous with received
packet handling, it is possible that packets for a notification will be handled
while handling the previous notification.  When handing the latter notification,
it is possible that there will be no packets left unhandled.  This means that a
timeout cannot be detected/inferred from a normal "no packet" empty return
value (i.e `Ptr{RecvPkt}(0)`).

After processing all of the packets, the caller must release the packets
by passing the `Ptr{RecvPkt}` object to `HashpipeIBVerbs.release_pkts()`.
"""
function recv_pkts(ctx, timeout_ms=-1)
    @ccall $(hashpipe_ibv_recv_pkts[])(
             Ref(ctx)::Ptr{Context},
             timeout_ms::Cint
            )::Ptr{RecvPkt}
end


"""
    release_pkts(ctx::Context, recv_pkt::Ptr{RecvPkt})::Nothing

Release a list of received packets after they have been processed.
"""
function release_pkts(ctx, recv_pkt)
    if recv_pkt != C_NULL
        rc = @ccall $(hashpipe_ibv_release_pkts[])(
                    Ref(ctx)::Ptr{Context},
                    recv_pkt::Ptr{RecvPkt}
                    )::Cint
        rc == 0 || error(Libc.strerror())
    end
    nothing
end

"""
    get_pkts(ctx::Context)::Ptr{SendPkt}
    get_pkts(ctx::Context, num_pkts::Integer)::Ptr{SendPkt}

Request a set of `num_pkts` free `SendPkt`s.  These are returned as a
`Ptr{SendPkt}` that points to the head of a linked list of `SendPkt` objects.
If no packets are available `Ptr{SendPkt}(0)` is returned.  It is possible for
the returned list to contain fewer than `num_pkts`.  If `num_pkts` is omitted,
it defaults to `ctx.send_pkt_num`.

The returned objects may have been used to send previous packets in which case
the length returned by `pktlen()` will reflect the length of those packets
rather then the size of the buffer space allocated for the packets.

After populating the buffers for these packets (see `wrap_send_bufs`), the
packets can be sent by passing the `Ptr{SendPkt}` object to
`HashpipeIBVerbs.send_pkts`.
"""
function get_pkts(ctx, num_pkts=ctx.send_pkt_num)
    Libc.errno(0)
    ppkts = @ccall $(hashpipe_ibv_get_pkts[])(
                     Ref(ctx)::Ptr{Context},
                     num_pkts::UInt32
                    )::Ptr{SendPkt}
    if ppkts == C_NULL && Libc.errno() != 0
        error(Libc.strerror())
    end
    ppkts
end

"""
    send_pkts(ctx::Context, ppkt::Ptr{SendPkt})::Nothing

Send the list of packets pointed to by `ppkt`.  This function posts the packets
for transmission and then returns; it does not wait for them to be transmitted.
"""
function send_pkts(ctx, send_pkt)
    if send_pkt != C_NULL
        # Always use QP 0 (since multi-QP support may be disappearing)
        rc = @ccall $(hashpipe_ibv_send_pkts[])(
                    Ref(ctx)::Ptr{Context},
                    send_pkt::Ptr{SendPkt}, 0::UInt32
                    )::Cint
        rc == 0 || (error(Libc.strerror()))
    end
    nothing
end

"""
Pass a `Ptr{SendPkt} for each and every SendPkt in `ctx` to `f`.  Iteration over
`Ptr{SendPkt}` pointers (e.g. as returned by `get_pkts`) iterates over a linked
list subset of `SendPkt`s.  A linked list subset is not guaranteed to include
every `SendPkt` object, so `foreach` is not guaranteed to cover every `SendPkt`
of `ctx`.  This function accesses all the `SendPkt` objects in `ctx`, passing
each one to `f`, which can be useful for initializing the `SendPkt` objects.
"""
function foreach_send_pkt(f, ctx)
    n = ctx.send_pkt_num
    ppkt = ctx.send_pkt_buf
    for _ in 1:n
        f(ppkt)
        ppkt += sizeof(SendPkt)
    end
    nothing
end

"""
Pass a `Ptr{RecvPkt} for each and every RecvPkt in `ctx` to `f`.  Iteration over
`Ptr{RecvPkt}` pointers (e.g. as returned by `get_pkts`) iterates over a linked
list subset of `RecvPkt`s.  A linked list subset is not guaranteed to include
every `RecvPkt` object, so `foreach` is not guaranteed to cover every `RecvPkt`
of `ctx`.  This function accesses all the `RecvPkt` objects in `ctx`, passing
each one to `f`, which can be useful for initializing the `RecvPkt` objects.
"""
function foreach_recv_pkt(f, ctx)
    n = ctx.recv_pkt_num
    ppkt = ctx.recv_pkt_buf
    for _ in 1:n
        f(ppkt)
        ppkt += sizeof(RecvPkt)
    end
    nothing
end

"""
    wrap_send_bufs(ctx::Context)::Vector{Vector{UInt8}}

Wrap the send packet buffers of `ctx` with `Vector{UInt8}` and return
`Vector{Vector{UInt8}}`.
"""
function wrap_send_bufs(ctx)
    n = ctx.send_pkt_num
    send_bufs = Vector{Vector{UInt8}}(undef, n)
    ppkt = ctx.send_pkt_buf
    for i in 1:n
        send_bufs[i] = unsafe_wrap(Array, Ptr{UInt8}(ppkt|>sg_list|>addr),
                                          ppkt|>sg_list|>sgelen)
        ppkt += sizeof(SendPkt)
    end
    send_bufs
end

"""
    wrap_recv_bufs(ctx::Context)::Vector{Vector{UInt8}}

Wrap the receive packet buffers of `ctx` with `Vector{UInt8}` and return
`Vector{Vector{UInt8}}`.
"""
function wrap_recv_bufs(ctx)
    n = ctx.recv_pkt_num
    recv_bufs = Vector{Vector{UInt8}}(undef, n)
    ppkt = ctx.recv_pkt_buf
    for i in 1:n
        recv_bufs[i] = unsafe_wrap(Array, Ptr{UInt8}(ppkt|>sg_list|>addr),
                                          ppkt|>sg_list|>sgelen)
        ppkt += sizeof(RecvPkt)
    end
    recv_bufs
end

end # module HashpipeIBVerbs
