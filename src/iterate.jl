import Base: IteratorSize
import Base: iterate
import Base: length

# Iterate all send pkts of a (pointer to a) hashpipe_ibv_context

"""
Tuple type for iterating complete list of send pkts in a haspipe_ibv_context.
Instances can be created via `(pctx, pctx.send_pkt_buf)`.
"""
# Not sure why the type for the first element (`pctx`) needs to have the extra
# parentheses, but they seem to be required.
SendPktIterator = Tuple{Cptr{Impl.var"(c\"struct hashpipe_ibv_context\")"},
                        Cptr{Cptr{c"struct hashpipe_ibv_send_pkt"}}}

# Iterate all `Cptr{c"struct hashpipe_ibv_send_pkt"}` contained in the first
# element of `tpctx`.  `tcptx` can be given as `(pctx, pctx.send_pkt_buf)`.

function Base.length(tpctx::SendPktIterator)
    tpctx[1].send_pkt_num[]
end

function Base.iterate(tpctx::SendPktIterator, i::Int=1)
  return (1 <= i <= length(tpctx)) ? (tpctx[1].send_pkt_buf[]+i-1, i+1) : nothing
end

# Iterate all recv pkts of a (pointer to a) hashpipe_ibv_context

"""
Tuple type for iterating complete list of recv pkts in a haspipe_ibv_context.
Instances can be created via `(pctx, pctx.recv_pkt_buf)`.
"""
# Not sure why the type for the first element (`pctx`) needs to have the extra
# parentheses, but they seem to be required.
RecvPktIterator = Tuple{Cptr{Impl.var"(c\"struct hashpipe_ibv_context\")"},
                        Cptr{Cptr{c"struct hashpipe_ibv_recv_pkt"}}}

# Iterate all `Cptr{c"struct hashpipe_ibv_recv_pkt"}` contained in the first
# element of `tpctx`.  `tcptx` can be given as `(pctx, pctx.recv_pkt_buf)`.

function Base.length(tpctx::RecvPktIterator)
    tpctx[1].recv_pkt_num[]
end

function Base.iterate(tpctx::RecvPktIterator, i::Int=1)
  return (1 <= i <= length(tpctx)) ? (tpctx[1].recv_pkt_buf[]+i-1, i+1) : nothing
end

# Iterate linked list pointed to by `Cptr{c"struct hashpipe_ibv_send_pkt"}`

function Base.IteratorSize(::Cptr{c"struct hashpipe_ibv_send_pkt"})
    Base.SizeUnknown()
end

function Base.iterate(ppkt::Cptr{c"struct hashpipe_ibv_send_pkt"}, next=ppkt)
  next != C_NULL ?
    (next, Cptr{c"struct hashpipe_ibv_send_pkt"}(UInt(next.wr.next[]))) :
    nothing
end

# Iterate linked list pointed to by `Cptr{c"struct ibv_send_wr"}`

function Base.IteratorSize(::Cptr{c"struct ibv_send_wr"})
    Base.SizeUnknown()
end

function Base.iterate(pwr::Cptr{c"struct ibv_send_wr"}, next=pwr)
  next != C_NULL ? (next, next.next[]) : nothing
end

# Iterate linked list pointed to by `Cptr{c"struct hashpipe_ibv_recv_pkt"}`

function Base.IteratorSize(::Cptr{c"struct hashpipe_ibv_recv_pkt"})
    Base.SizeUnknown()
end

function Base.iterate(ppkt::Cptr{c"struct hashpipe_ibv_recv_pkt"}, next=ppkt)
  next != C_NULL ?
    (next, Cptr{c"struct hashpipe_ibv_recv_pkt"}(UInt(next.wr.next[]))) :
    nothing
end

# Iterate linked list pointed to by `Cptr{c"struct ibv_recv_wr"}`

function Base.IteratorSize(::Cptr{c"struct ibv_recv_wr"})
    Base.SizeUnknown()
end

function Base.iterate(pwr::Cptr{c"struct ibv_recv_wr"}, next=pwr)
  next != C_NULL ? (next, next.next[]) : nothing
end
