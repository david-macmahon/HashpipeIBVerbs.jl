using HashpipeIBVerbs
using Sockets
using Dates

interface = "eth4"

rem_mac = mac"02:02:0a:0a:0a:0a" # Remote MAC (skip ARP)
rem_ip = ip"10.10.10.10" # Remote IP

loc_mac = mac"02:02:0a:0a:0a:0b" # Local MAC (for `interface`)
loc_ip = ip"10.10.10.11" # Local IP (for `interface`)

"""
Compute the 16 bit checksum value of v.

This checksum is used in many Internal protocols.
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

function dibas_udp_size()
    # Eth/IP/UDP fields
    eth_sz = 6 + 6 + 2
    ip_sz = 5 * sizeof(UInt32)
    udp_sz = 4 * sizeof(UInt16)
    # Application fields
    hdr_sz = 8
    payload_sz = 8192
    footer_sz = 3 * sizeof(UInt64)

    return eth_sz + ip_sz + udp_sz + hdr_sz + payload_sz + footer_sz
end

function dibas_udp_pkt!(buf; dst_mac, src_mac, dst_ip, src_ip,
                        src_port=10000, dst_port=60000,
                        payload::AbstractArray{UInt8}=zeros(UInt8, 8192),
                        node_id=0, mcount=0
                        )

    @assert length(payload) == 8192 "payload must be 8192 bytes"

    # Eth/IP/UDP fields
    eth_sz = 6 + 6 + 2
    ip_sz = 5 * sizeof(UInt32)
    udp_sz = 4 * sizeof(UInt16)
    # Application fields
    hdr_sz = 8
    payload_sz = 8192
    footer_sz = 3 * sizeof(UInt64)

    # Ethernet header

    eth_hdr = vcat(mac(dst_mac), mac(src_mac), 0x08, 0x00)

    # IP header

    ip_hdr = UInt32[
        0x4500_0000 | (ip_sz + udp_sz + hdr_sz + payload_sz + footer_sz),  # (verihl.tos)_(length)
        0x0000_4000, # (id)|(flags.fragoff)
        0x4011_0000,   # (ttl.proto)_(csum*) [ICMP is proto 1]
        UInt32(src_ip),
        UInt32(dst_ip)
    ]

    ip_csum = checksum16(hton.(ip_hdr))
    ip_hdr[3] |= ip_csum # host order!

    # UDP header
    udp_hdr = UInt16[
        src_port, dst_port,
        udp_sz + hdr_sz + payload_sz + footer_sz, 0
    ]

    # App header
    app_hdr = [(UInt64(node_id) << 56) | (UInt64(mcount) & 0x00ff_ffff_ffff_ffff)]

    # App footer
    footer = UInt64[0, 0xaaaa_aaaa_aaaa_a800, 0xaaaa_aaaa_aaaa_a800]

    # Calculate indexing
    eth_idx     = (1:eth_sz)
    ip_idx      = (1:ip_sz)      .+ last(eth_idx)
    udp_idx     = (1:udp_sz)     .+ last(ip_idx)
    hdr_idx     = (1:hdr_sz)     .+ last(udp_idx)
    payload_idx = (1:payload_sz) .+ last(hdr_idx)
    footer_idx  = (1:footer_sz)  .+ last(payload_idx)

    # Populate buffer
    buf[eth_idx] .= eth_hdr
    buf[ip_idx]  .= reinterpret(UInt8, hton.(ip_hdr))
    buf[udp_idx] .= reinterpret(UInt8, hton.(udp_hdr))
    buf[hdr_idx] .= reinterpret(UInt8, hton.(app_hdr))
    buf[payload_idx] .= reinterpret(UInt8, hton.(payload))
    buf[footer_idx]  .= reinterpret(UInt8, hton.(footer))

    return eth_sz + ip_sz + udp_sz + hdr_sz + payload_sz + footer_sz
end

#=
"""
Set the mcount field of DIBAS packet `buf` to the seven least significant bytes
of `mcount`, mhich must be given in host byte order.  If `node_id` is given (and
not `nothing`), the node_id field will also be updated, otherwise the original
node_id field in `buf` is preserved.
"""
=#
"""
Set the mcount field of DIBAS packet `buf` to the seven least significant bytes
of `mcount`, mhich must be given in host byte order.
"""
function dibas_mcount!(buf, mcount)
    unsafe_store!(Ptr{Int64}(pointer(buf)+42), hton(mcount))
    nothing
end

function send_dibas_pkts(ctx, send_bufs, num_to_send=10^6; init_mcount=0)
    # MCOUNT value
    mcount = init_mcount

    # Packet stats variables
    pkts_sent = 0
    start = now()
    payload_sz = 8192

    while pkts_sent < num_to_send
        # Get packet to send
        pkts = HashpipeIBVerbs.get_pkts(ctx, 500)

        # Loop over send packets to set mcount
        for pkt in pkts
            dibas_mcount!(send_bufs[pkt], mcount)
            mcount += 1
            pkts_sent += 1
        end

        # Send packets!
        HashpipeIBVerbs.send_pkts(ctx, pkts)
    end

    stop = now()
    ms = stop - start
    bytes_sent = pkts_sent * payload_sz
    gbps = 8 * bytes_sent / ms.value / 10^6

    pkts_sent, bytes_sent, ms, gbps
end

function main(interface, rem_mac, rem_ip, loc_mac, loc_ip, num_to_send=10^6)
    # Initialize context
    ctx = HashpipeIBVerbs.init(interface, 1000, 1, 9000)

    # Wrap send packet buffers
    send_bufs = wrap_send_bufs(ctx)

    # Prepopulate packet contents
    for (i, buf) in enumerate(send_bufs)
        dibas_udp_pkt!(buf,
                       dst_mac=rem_mac, src_mac=loc_mac,
                       dst_ip=rem_ip, src_ip=loc_ip, node_id=5,
                       payload=reinterpret(UInt8, hton.(fill(i%UInt16, 4096)))
                      )
    end

    # Preset the length of all send packets
    foreach_send_pkt(p->len!(p, dibas_udp_size()), ctx)

    pkts_sent, bytes_sent, ms, gbps = send_dibas_pkts(ctx, send_bufs, num_to_send)

    # Show summary
    @info "sent $pkts_sent DIBAS packets [$bytes_sent bytes] in $(canonicalize(ms)) [$(round(gbps, sigdigits=5)) Gbps]"

    # Shutdown
    HashpipeIBVerbs.shutdown(ctx)
end

if abspath(PROGRAM_FILE) == @__FILE__
    n = 10^7
    isempty(ARGS) || (n = something(tryparse(Float64, ARGS[1]), n))
    main("eth4", rem_mac, rem_ip, loc_mac, loc_ip, round(Int,n))
end
