# HashpipeIBVerbs.jl

A Julia interface to the Hashpipe IB Verbs library.

## Quick Start

```julia
using HashpipeIBVerbs
using PrettyPrint

# Initialize library to use `eth4` network interface, 2 packet send buffers,
# 2 packet receive buffers, and 9 KiB max packet size.
ctx = HashpipeIBVerbs.init("eth4", 2, 2, 9*1024)

# Wrap the receive buffers as `Vector{UInt8}` (returns `Vector{Vector{UInt8}`)
recv_bufs = HashpipeIBVerbs.wrap_recv_bufs(ctx)

# Add a "flow" rule to capture packet sent to MAC address 01:80:c2:00:00:00
# which is the destination MAC address for Spanning Tree Protocol packets often
# sent by switches.
HashpipeIBVerbs.flow(ctx, 1, dst_mac=mac"01:80:c2:00:00:00")

# Loop 10 times
for i in 1:10
    # Receive packet(s)
    pkts = HashpipeIBVerbs.recv_pkts(ctx)

    # Iterate through `pkts`
    for pkt in pkts
        # Pretty print packet data.  Notice how `pkt` is used as an index into
        # `recv_bufs` to get `Vector{UInt8}` corresponding the the received
        # packet's receive buffer.
        pprintln(recv_bufs[pkt][1:pktlen(pkt)])
    end

    # Release packet(s)
    HashpipeIBVerbs.release_pkts(ctx, pkts)
end

# Shutdown (frees resources allocated by init)
HashpipeIBVerbs.shutdown(ctx)

# Prevent the use of `recv_bufs` since the underlying memory is now invalid.
# This is only really needed if the `recv_bufs` variable will live longer.  In
# this case, the script is ending so it is not really needed, but it is shown
# here for illustrative purposes.
recv_bufs = nothing
```

## HashpipeIBVerbs Life Cycle

The HashpipeIBVerbs package requires the user to follow certain use patterns to
ensure proper behavior.  The basic steps are:

1. Initialize a `Context` via `HashpipeIBVerbs.init()`
2. Wrap the send and/or receive buffers with `Vector{UInt8}`
3. Send and/or receive packets as desired
4. Shutdown the `context`
5. Forget wrapper Vectors (optional, but advised)

### Initialization

Initialization requires 5 pieces of information:

1. Name of the interface to use (e.g. "eth4")
2. Number of send packet buffers
3. Number of receive packet buffers
4. Max packet size to support (i.e. size of each packet buffer)
5. Max number of flow rules to support (defaults to 16)

These parameters are passed to the `HashpipeIBVerbs.init()` function which
returns a `Context` object that corresponds to the `hashpipe_ibv_context`
structure of the underlying `hashpipe_ibverbs` library.  This object is passed
to other `HashpipeIBVerbs` functions.

Currently only "library managed" packet buffers are supported.

### Wrapping the send and/or receive buffers

Part of the initialization allocates send packet buffers and receive packet
buffers.  These buffers can be wrapped as a `Vector{UInt8}` to provide a
convenient way to access the packet data.  Separate functions are provided to
wrap the send and receive buffers:

- `wrap_send_bufs(ctx)` wraps the send packet buffers
- `wrap_recv_bufs(ctx)` wraps the receive packet buffers

Both functions return `Vector{Vector{UInt8}}`.  Each `Vector{UInt8}` corresponds
to a specific packet buffer.  The caller must ensure that they are working with
the `Vector` corresponding to the packet that they are handling as explained
below.

### Sending packets

The user is responsible for constructing properly structured packets that are
to be sent via `HashpipeIBVerbs`, including the Ethernet header and any other
headers/payload that may be desired.  Prior to sending any packets, some
"boilerplate" packet contents (e.g. source MAC address) can be stored in the
appropriate location of the send packet buffers.  To send one or more packets,
the user must first acquire the packet(s) from the library, set/modify the
contents as desired, then send the packets.  Sending the packets actually just
"posts" them to the IB Verbs layer for transmission.  Once a packet is posted,
the corresponding packet buffer should not be modified until after it has been
transmitted.  The best way to ensure this is to only modify packet buffers for
packets that have been acquired from the library (posted packets still pending
transmission are not acquirable in this way).

#### Acquiring packets

Packets to be sent can be acquired using:

```julia
pkts = HashpipeIBVerbs.get_pkts(ctx, num_pkts)
```

`num_pkts` specifies the desired number of packets to acquire.  The return value
is a `Ptr{SendPkt}` (i.e. a pointer to a send packet) that points to a possibly
empty linked list of packets.  For this reason, the return value is often stored
in a variable with a pluralized name (e.g. `pkts`) when `num_pkts > 1`.  The
returned value must be iterated over to access all the acquired packets:

```julia
for pkt in pkts
    # Modify the contents of the "send buffer" for `pkt`
end
```

`isempty(pkts)` can be used to test for an empty linked list, but this is often
not needed since iterating over an empty linked list does nothing anyway.

#### Modifying the packet buffer contents

Once acquired, the packet's send buffer can be accessed from the `Vector`
returned by `wrap_send_bufs(ctx)` by using the `Ptr{SendPkt}` object itself as
an index into the `Vector`.  The resultant `Vector{UInt8}` contains the data
that will be sent to the network.  The user should set this as desired.  The
packet buffer must include the Ethernet header and any other headers/payloads
required for the packet format being sent.  The length of the packet to be sent
must be set using `pktlen!(pkt, n)`.  Continuing the previous example:

```julia
for pkt in pkts
    # Modify the contents of the "send buffer" for `pkt`
    # `send_bufs` holds the value from a previous call to `wrap_send_bufs(ctx)`
    send_bufs[pkt][1:6] = dst_mac
    # etc...
    # Set packet length
    pktlen!(pkt, n)
end
```

#### Sending the packet(s)

After the contents have been set as desired and the packet length(s) have been
set, the packets can then be sent by passing the acquired `Ptr{SendPkt}` object
to `HashpipeIBVerbs.send_pkts(pkts)`.  This call just posts (i.e. enqueues) the
packets to be sent.  It does not wait for the packets to be sent.

### Receiving packets

In order to receive packets, the user must first establish "flow rules" to tell
the library which incoming packets it wishes to receive.  After flow rules are
established, received packets can be obtained by calling
`HashpipeIBVerbs.recv_pkts`.  As with acquired send packets, the received
packets can be iterated over and used to index into the `Vector` of wrapped
receive buffers to get access to the data of the received packets.  After the
received packets have been handled, they must be released back to the library to
allow more packets to be received.

#### Establishing flow rules
Flow rules can be established by calling `HashpipeIBVerbs.flow()`.  The online
documentation ("doc string") for that function is very thorough and will not be
repeated here.

#### Receiving packets

Received packets can be obtained by calling:

```julia
pkts = HashpipeIBVerbs.recv_pkts(ctx, timeout_ms)
```

This function will wait for packets to be received or for `timeout_ms`
milliseconds, whichever happens first, before returning.  Timeout values less
than 0 mean "forever" (the default if the `timeout_ms` argument is omitted).
The return value will be a `Ptr{RecvPkt}` (i.e. a pointer to a receive packet)
that points to a possibly empty linked list of packets.  The returned value must
be iterated over to access all the returned packets:

```julia
for pkt in pkts
    # Access the contents of the "receive buffer" for `pkt`
end
```

`isempty(pkts)` can be used to test for an empty linked list, but this is often
not needed since iterating over an empty linked list does nothing anyway.

A pointer to an empty linked list is returned if `timeout_ms` milliseconds
elapse with no packets being received, but also in the case where received
packets were returned by a previous call to `HashpipeIBVerbs.recv_pkts()`.  This
latter case can happen because it is possible for the library to receive packets
before handling the notification for those packets.  This means that the user
should be prepared to handle an empty linked list even when `timeout_ms` is
negative.

#### Accessing the received packet contents

The received packets' data buffers can be accessed from the `Vector` returned by
`wrap_recv_bufs(ctx)` by using the `Ptr{RecvPkt}` objects themselves as an index
into the `Vector`.  The first `pktlen(pkt)` values of the resultant
`Vector{UInt8}` contain the received packet data.  This includes the Ethernet
header and any other data present in the packet.  Continuing the previous
example:

```julia
for pkt in pkts
    # Format the source MAC address
    # `recv_bufs` holds the value from a previous call to `wrap_recv_bufs(ctx)`
    src_mac = join(string.(recv_bufs[pkt][7:12], base=16, pad=2), ':')
    # Get packet length
    n = pktlen(pkt)
    println("got ", n, " byte packet from ", src_mac)
end
```

#### Releasing packets

After handling/processing the data of the received packets, the packet objects
must be released back to the library by passing the `Ptr{RecvPkt}` object
`HashpipeIBVerbs.release_pkts(pkts)`.  If the library runs out of packet objects
into which to receive packets incoming packets may be dropped, so to prevent
packet loss it is important to turn around received packet objects as quickly as
possible.  Currently there is a one-to-one mapping between packet objects and
packet buffers, but future versions of `HashpipeIBVerbs` may provide more
flexibility in this area to facilitate rapid packet object turnaround.

### Shutdown

When done using the `Context`, the resource allocated with `HashpipeIBVerbs.init`
can be freed by calling `HashpipeIBVerbs.shutdown(ctx)`.  This will free all
of the library-managed memory, including the packet data buffers that may have
been wrapped by `wrap_send_bufs` or `wrap_recv_bufs` thereby rendering those
invalid.  Future attempts to access their contents may cause memory
(segmentation) faults, i.e. the process may crash.

### Forget wrapper Vectors

After shutting down the `Context`, any `Vector`s wrapping the send or receive
buffers should not be used.  It is advised to set the variables holding these
references to `nothing` or some other "safe" value if these variables will be
long lived.

## Putting it all together

The `examples/ping_demo.jl` script uses `HashpipeIBVerbs` to implement a basic
ICMP echo request/reply utility.  To simplify initialization, the local network
interface to be used (`interface`) and the remote and local MAC and IP
addresses (`rem_mac`, `rem_ip`, `loc_mac`, `loc_ip`) are specified at the top of
the script and must be changed to match your local setup.

Versions of the underlying `hashpipe_ibverbs` library that do not include a fix
for how send work completion notifications are requested will show two ICMP
sequence numbers being sent on the first call to `HashpipeIBVerbs.send_pkts`,
but on subsequent calls only one sequence number will be sent per call.  Newer
versions of the underlying library (as of `hashpipe` commit `98caca4`) will show
two sequence numbers being sent on each and every call.
