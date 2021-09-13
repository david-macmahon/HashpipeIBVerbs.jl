import Base: IteratorSize
import Base: iterate

# Iterate linked list of `struct hashpipe_ibv_recv_pkt`
function Base.IteratorSize(::c"struct hashpipe_ibv_send_pkt")
    Base.SizeUnknown()
end

function Base.iterate(pkt::c"struct hashpipe_ibv_send_pkt")
  (pkt, Cptr{c"struct hashpipe_ibv_send_pkt"}(UInt(pkt.wr.next)))
end

function Base.iterate(::c"struct hashpipe_ibv_send_pkt", next::Cptr{c"struct hashpipe_ibv_send_pkt"})
  next == C_NULL && return nothing
  pkt = next[]
  (pkt, Cptr{c"struct hashpipe_ibv_send_pkt"}(UInt(pkt.wr.next)))
end

# Iterate linked list of `struct ibv_send_wr`
function Base.IteratorSize(::c"struct ibv_send_wr")
    Base.SizeUnknown()
end

function Base.iterate(wr::c"struct ibv_send_wr")
  (wr, wr.next)
end

function Base.iterate(::c"struct ibv_send_wr", next::Cptr{c"struct ibv_send_wr"})
  next == C_NULL && return nothing
  wr = next[]
  (wr, wr.next)
end

# Iterate linked list of `struct hashpipe_ibv_recv_pkt`
function Base.IteratorSize(::c"struct hashpipe_ibv_recv_pkt")
    Base.SizeUnknown()
end

function Base.iterate(pkt::c"struct hashpipe_ibv_recv_pkt")
  (pkt, Cptr{c"struct hashpipe_ibv_recv_pkt"}(UInt(pkt.wr.next)))
end

function Base.iterate(::c"struct hashpipe_ibv_recv_pkt", next::Cptr{c"struct hashpipe_ibv_recv_pkt"})
  next == C_NULL && return nothing
  pkt = next[]
  (pkt, Cptr{c"struct hashpipe_ibv_recv_pkt"}(UInt(pkt.wr.next)))
end

# Iterate linked list of `struct ibv_recv_wr`
function Base.IteratorSize(::c"struct ibv_recv_wr")
    Base.SizeUnknown()
end

function Base.iterate(wr::c"struct ibv_recv_wr")
  (wr, wr.next)
end

function Base.iterate(::c"struct ibv_recv_wr", next::Cptr{c"struct ibv_recv_wr"})
  next == C_NULL && return nothing
  wr = next[]
  (wr, wr.next)
end
