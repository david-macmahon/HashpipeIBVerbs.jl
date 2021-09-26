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

"""
Set the node_id and mcount fields of DIBAS packet `buf` to the value of
`mcount`, mhich must be given in host byte order.  The most significant byte of
`mcount` is used as the `node_id` while the lower 7 bytes are the actual
`mcount`.
"""
function dibas_mcount!(buf, mcount)
    unsafe_store!(Ptr{UInt64}(pointer(buf)+42), hton(mcount))
    nothing
end

function send_dibas_pkts(ctx, send_bufs, num_to_send=10^6, desired_bps::Float32=0.0; init_mcount::UInt64=UInt64(0))
  # MCOUNT value (has node_id is uppermost 8 bits)
    mcount = init_mcount

    # Packet stats variables
    pkts_sent = 0
    start = now()
    start_sec = datetime2unix(start)
    payload_sz = 8192
    packet_sz = dibas_udp_size()
    packet_bits = 8 * packet_sz

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

        # Throttle
        if desired_bps > 0
            # data_time is the time corresponding to the data sent thus at the
            # desired rate.
            #
            #                   bits_sent
            # seconds = -------------------------
            #            desired_bits_per_second
            #
            data_time = pkts_sent * packet_bits / desired_bps
            # elapsed_time is the time that has elapsed since we started sending
            # packets.
            elapsed_time = time() - start_sec

            # Compute sleep time needed to allow elapsed_time to catch up to
            # data_time.
            sleep_time = data_time - elapsed_time

            # If we are ahead of schedule by more than a tolerable threshold
            if sleep_time > 0.005f0
                # Sleep!
                sleep(sleep_time)
            end
        end
    end

    stop = now()
    ms = stop - start
    payload_bytes_sent = pkts_sent * payload_sz
    total_bytes_sent = pkts_sent * packet_sz
    payload_gbps = 8 * payload_bytes_sent / ms.value / 10^6
    total_gbps = 8 * total_bytes_sent / ms.value / 10^6

    pkts_sent, payload_bytes_sent, total_bytes_sent, ms, payload_gbps, total_gbps
end

function main(interface, rem_mac, rem_ip, loc_mac, loc_ip, num_to_send=10^6, desired_bps::Float32=0; node_id=5)
    # Initialize context
    ctx = HashpipeIBVerbs.init(interface, 1000, 1, 9000)

    # Wrap send packet buffers
    send_bufs = wrap_send_bufs(ctx)

    # Prepopulate packet contents
    for (i, buf) in enumerate(send_bufs)
        dibas_udp_pkt!(buf,
                       dst_mac=rem_mac, src_mac=loc_mac,
                       dst_ip=rem_ip, src_ip=loc_ip, node_id=node_id,
                       payload=reinterpret(UInt8, hton.(fill(i%UInt16, 4096)))
                      )
    end

    # Preset the length of all send packets
    foreach_send_pkt(p->pktlen!(p, dibas_udp_size()), ctx)

    init_mcount = UInt64(node_id) << 56
    pkts, payload_bytes, total_bytes, ms, payload_gbps, total_gbps =
        send_dibas_pkts(ctx, send_bufs, num_to_send, desired_bps; init_mcount=init_mcount)

    payload_gbps = round(payload_gbps, sigdigits=5)
    total_gbps = round(total_gbps, sigdigits=5)

    # Show summary
    @info "sent $pkts DIBAS packets [$payload_bytes/$total_bytes bytes] in $(
        canonicalize(ms)) [$payload_gbps/$total_gbps Gbps]"

    # Shutdown
    HashpipeIBVerbs.shutdown(ctx)
end

if abspath(PROGRAM_FILE) == @__FILE__
    n = 10^7
    gbps = 0f0 # Fast as possible
    length(ARGS) > 0 && (n = something(tryparse(Float64, ARGS[1]), n))
    length(ARGS) > 1 && (gbps = something(tryparse(Float32, ARGS[2]), gbps))
    main("eth4", rem_mac, rem_ip, loc_mac, loc_ip, round(Int,n), 1f9*gbps)
end
