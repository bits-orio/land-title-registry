#!/usr/bin/env python3
"""A slow network between one Factorio client and a server on this machine.

usage: dev/udp-delay.py <server port> <delay ms> <port file>

Listens on a free localhost UDP port (written to <port file>) and relays every
datagram between the client that connects there and the server, each one held
for <delay ms> on its way: a round trip takes twice that. The server then
measures the client as a far-away one and schedules its input further ahead
(100 ms each way was measured as about 17 ticks on 2.1.25), which the config
setting minimum-latency-in-multiplayer was measured not to do. Runs until
killed.
"""
import asyncio
import sys

server = ("127.0.0.1", int(sys.argv[1]))
delay = float(sys.argv[2]) / 1000
port_file = sys.argv[3]


class Side(asyncio.DatagramProtocol):
    """One socket of the relay; what it receives leaves by `other` later."""

    def __init__(self):
        self.transport, self.other, self.peer = None, None, None

    def connection_made(self, transport):
        self.transport = transport

    def datagram_received(self, data, addr):
        self.peer = addr
        target = self.other.peer
        if target:
            asyncio.get_running_loop().call_later(delay, self.other.transport.sendto, data, target)


async def main():
    loop = asyncio.get_running_loop()
    front, back = Side(), Side()
    front.other, back.other = back, front
    back.peer = server
    await loop.create_datagram_endpoint(lambda: front, local_addr=("127.0.0.1", 0))
    await loop.create_datagram_endpoint(lambda: back, local_addr=("127.0.0.1", 0))
    with open(port_file, "w") as out:
        out.write(str(front.transport.get_extra_info("sockname")[1]))
    await asyncio.Event().wait()


asyncio.run(main())
