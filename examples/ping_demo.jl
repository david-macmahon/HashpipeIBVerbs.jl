using HashpipeIBVerbs
using Sockets
using Dates

interface = "eth4"

rem_mac = mac"02:02:0a:0a:0a:0a" # Remote MAC (skip ARP)
rem_ip = ip"10.10.10.10"         # Remote IP

loc_mac = mac"02:02:0a:0a:0a:0b" # Local MAC (for `interface`)
loc_ip = ip"10.10.10.11"         # Local IP (for `interface`)

"""
Compute the 16 bit checksum value of v.

This checksum is used in many Internet protocols.
"""
function checksum16(v::AbstractVector{UInt8})::UInt16
    csum = sum(v[1:2:end]) << 8
    csum += sum(v[2:2:end])
    csum = (csum & 0xffff) + (csum>>16)
    csum = (csum & 0xffff) + (csum>>16)
    UInt16((~csum) & 0xffff)
end

function checksum16(v::AbstractVector)::UInt16
    checksum16(reinterpret(UInt8, v))
end

function icmp_echo_req!(buf, dst_mac, src_mac, dst_ip, src_ip, icmp_id, seq,
                        payload="Hello from HashpipeIBVerbs.jl! :)")
    # Work backwards from payload

    payload_bytes = codeunits(payload)
    payload_sz = sizeof(payload_bytes)

    # ICMP header

    icmp_id_seq = (UInt32(icmp_id) << 16) | (seq & 0xffff)

    icmp_hdr = UInt32[
        0x0800_0000, # (type.code)_(csum*)
        icmp_id_seq, # (id)_(seq)
    ]

    icmp_sz = sizeof(icmp_hdr)

    # IP header

    ip_id_fragoff = 0x0000_4000
    ip_sz = 5 * sizeof(UInt32)

    ip_hdr = UInt32[
        0x4500_0000 | (ip_sz + icmp_sz + payload_sz),  # (verihl.tos)_(length)
        ip_id_fragoff, # (id)|(flags.fragoff)
        0x4001_0000,   # (ttl.proto)_(csum*) [ICMP is proto 1]
        UInt32(src_ip),
        UInt32(dst_ip)
    ]

    ip_csum = checksum16(hton.(ip_hdr))
    ip_hdr[3] |= ip_csum # host order!

    # Ethernet header

    eth_hdr = vcat(dst_mac, src_mac, 0x08, 0x00)
    eth_sz = sizeof(eth_hdr)

    # Calculate indexing
    eth_idx     = (1:eth_sz)
    ip_idx      = (1:ip_sz)      .+ last(eth_idx)
    icmp_idx    = (1:icmp_sz)    .+ last(ip_idx)
    payload_idx = (1:payload_sz) .+ last(icmp_idx)

    # Populate buffer
    buf[eth_idx] .= eth_hdr
    buf[ip_idx]  .= reinterpret(UInt8, hton.(ip_hdr))
    buf[icmp_idx] .= reinterpret(UInt8, hton.(icmp_hdr))
    buf[payload_idx] .= payload_bytes

    # Compute and store ICMP checksum
    icmp_csum = checksum16(buf[first(icmp_idx):last(payload_idx)])
    buf[first(icmp_idx)+2] = icmp_csum >> 8
    buf[first(icmp_idx)+3] = icmp_csum & 0xff

    return eth_sz + ip_sz + icmp_sz + payload_sz
end

# Initialize context
ctx = HashpipeIBVerbs.init(interface, 2, 20, 100)

# Wrap packet buffers
send_bufs=wrap_send_bufs(ctx)
recv_bufs=wrap_recv_bufs(ctx)

# Setup flow for all IP traffic from remote IP to local IP This can scoop up
# more than we care for, so use with caution!!!  Do not use this example
# on a link with lots of other IP traffic!!!!
HashpipeIBVerbs.flow(ctx, 1,
                     dst_mac=loc_mac, src_mac=rem_mac, ether_type=0x0800,
                     src_ip=rem_ip, dst_ip=loc_ip)

# Pick an ICMP ID value
icmp_id = rand(UInt16)
@info "using ICMP ID $(icmp_id)"

# Packet counters
seq = 0
replies = 0

while seq < 10
    # Get packet to send
    spkts = HashpipeIBVerbs.get_pkts(ctx, 2)

    # Loop over send packets to set contents
    sent_seqs = Int[]
    for spkt in spkts
        global seq += 1
        push!(sent_seqs, seq)
        pktlen!(spkt, icmp_echo_req!(send_bufs[spkt],
                rem_mac, loc_mac, rem_ip, loc_ip, icmp_id, seq))
    end

    # Send packets!
    HashpipeIBVerbs.send_pkts(ctx, spkts)
    @info "$(now()) sent seqs $(sent_seqs)"

    # Get replies, if any
    rpkts = HashpipeIBVerbs.recv_pkts(ctx, 10)

    # Loop over receive packets
    for rpkt in rpkts
        data = recv_bufs[rpkt]
        # If IP proto is ICMP and ICMP type is echo reply
        if data[1+14+9] == 0x01 && data[1+14+20] == 0x00
            rep_id, rep_seq = ntoh.(reinterpret(UInt16, @view data[(14+20+4).+(1:4)]))
            @info "$(now()) got ICMP Reply for ID $(rep_id) seq $(rep_seq)"
            global replies += 1
        else
            @info "$(now()) got misc packet with length $(rpkt.length[])"
        end
    end

    # Release packets
    HashpipeIBVerbs.release_pkts(ctx, rpkts)

    # Delay a little while if you want
    #sleep(1)
end

# Show summary.  It is not unusual to leave some ICMP Echo Reply packets "in the
# queue" since calls to `recv_pkts` are one-to-one with calls to `send_pkts`,
# but sometimes `recv_pkts` returns no packets due to some packets being
# processed before the underlying `hashpipe_ibverbs` library "sees" their
# completion notificastion.
@info "sent $(seq) ICMP Echo Request packets, received $(replies) ICMP Echo Reply packets"

# Shutdown
HashpipeIBVerbs.shutdown(ctx)

# Forget send/recv buffers
send_bufs = nothing
recv_bufs = nothing
