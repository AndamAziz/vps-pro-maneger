#!/usr/bin/env python3
"""HTTP-upgrade -> SSH tunnel ("SSH over WebSocket" payload tunnel).

Accepts the HTTP request that tunnel apps (HTTP Custom, HTTP Injector, NapsternetV, ...) send, e.g.
    GET / HTTP/1.1[crlf]Host: example.com[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]
answers "HTTP/1.1 101 Switching Protocols" and then pipes the raw TCP stream to the local sshd.
Any Host / path / extra headers are accepted, so the payload host can be changed freely.

Normal browsers (no Upgrade header) get a harmless 200 page; CONNECT gets "200 Connection established".
"""
import argparse
import asyncio
import socket

RESP_101 = (b"HTTP/1.1 101 Switching Protocols\r\n"
            b"Upgrade: websocket\r\nConnection: Upgrade\r\n\r\n")
RESP_200 = b"HTTP/1.1 200 Connection established\r\n\r\n"
BODY = b"<html><body><h1>It works!</h1></body></html>\n"
RESP_PAGE = (b"HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: "
             + str(len(BODY)).encode() + b"\r\nConnection: close\r\n\r\n" + BODY)
MAX_HEADER = 16384


async def pipe(reader, writer):
    try:
        while True:
            data = await reader.read(65536)
            if not data:
                break
            writer.write(data)
            await writer.drain()
    except (ConnectionError, asyncio.CancelledError, OSError):
        pass
    finally:
        try:
            writer.close()
        except Exception:
            pass


def keepalive(writer):
    sock = writer.get_extra_info("socket")
    if sock is not None:
        try:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        except OSError:
            pass


def make_handler(ssh_host, ssh_port):
    async def handle(reader, writer):
        keepalive(writer)
        try:
            head = await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"), timeout=15)
        except (asyncio.IncompleteReadError, asyncio.LimitOverrunError, asyncio.TimeoutError, ConnectionError):
            writer.close()
            return
        text = head.decode("latin-1").lower()
        first = text.split("\r\n", 1)[0]
        if "upgrade: websocket" in text or "upgrade:websocket" in text:
            reply = RESP_101
        elif first.startswith("connect "):
            reply = RESP_200
        else:
            writer.write(RESP_PAGE)
            try:
                await writer.drain()
            finally:
                writer.close()
            return
        try:
            sreader, swriter = await asyncio.open_connection(ssh_host, ssh_port)
        except OSError:
            writer.write(b"HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n")
            writer.close()
            return
        keepalive(swriter)
        writer.write(reply)
        await writer.drain()
        await asyncio.gather(pipe(reader, swriter), pipe(sreader, writer))
    return handle


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--listen", default="127.0.0.1:10810", help="host:port to listen on")
    ap.add_argument("--ssh", default="127.0.0.1:22", help="host:port of sshd")
    a = ap.parse_args()
    lh, lp = a.listen.rsplit(":", 1)
    sh, sp = a.ssh.rsplit(":", 1)
    server = await asyncio.start_server(make_handler(sh, int(sp)), lh, int(lp), limit=MAX_HEADER)
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
