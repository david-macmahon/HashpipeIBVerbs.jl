import Base: IteratorSize
import Base: iterate

# Iterate linked list pointed to by `Cptr{c"struct hashpipe_ibv_send_pkt"}`
function Base.IteratorSize(::Cptr{c"struct hashpipe_ibv_send_pkt"})
    Base.SizeUnknown()
end

function Base.iterate(ppkt::Cptr{c"struct hashpipe_ibv_send_pkt"})
  ppkt == C_NULL && return nothing
  (ppkt, Cptr{c"struct hashpipe_ibv_send_pkt"}(UInt(ppkt.wr.next[])))
end

function Base.iterate(::Cptr{c"struct hashpipe_ibv_send_pkt"}, next::Cptr{c"struct hashpipe_ibv_send_pkt"})
  Base.iterate(next)
end

# Iterate linked list pointed to by `Cptr{c"struct ibv_send_wr"}`
function Base.IteratorSize(::Cptr{c"struct ibv_send_wr"})
    Base.SizeUnknown()
end

function Base.iterate(pwr::Cptr{c"struct ibv_send_wr"})
  pwr == C_NULL && return nothing
  (pwr, pwr.next[])
end

function Base.iterate(::Cptr{c"struct ibv_send_wr"}, next::Cptr{c"struct ibv_send_wr"})
  Base.iterate(next)
end

# Iterate linked list pointed to by `Cptr{c"struct hashpipe_ibv_recv_pkt"}`
function Base.IteratorSize(::Cptr{c"struct hashpipe_ibv_recv_pkt"})
    Base.SizeUnknown()
end

function Base.iterate(ppkt::Cptr{c"struct hashpipe_ibv_recv_pkt"})
  ppkt == C_NULL && return nothing
  (ppkt, Cptr{c"struct hashpipe_ibv_recv_pkt"}(UInt(ppkt.wr.next[])))
end

function Base.iterate(::Cptr{c"struct hashpipe_ibv_recv_pkt"}, next::Cptr{c"struct hashpipe_ibv_recv_pkt"})
  Base.iterate(next)
end

# Iterate linked list pointed to by `Cptr{c"struct ibv_recv_wr"}`
function Base.IteratorSize(::Cptr{c"struct ibv_recv_wr"})
    Base.SizeUnknown()
end

function Base.iterate(pwr::Cptr{c"struct ibv_recv_wr"})
  pwr == C_NULL && return nothing
  (pwr, pwr.next[])
end

function Base.iterate(::Cptr{c"struct ibv_recv_wr"}, next::Cptr{c"struct ibv_recv_wr"})
  Base.iterate(next)
end
