#!/usr/bin/env python3
"""I/O bridge between the Big Cursor service and Hyprland's request socket.

stdout: "<x> <y>" each time the pointer moves.
stdin:  "setcursor <theme> <size>" lines, forwarded to Hyprland. When several
        arrive at once only the newest is sent, so a slow compositor never
        falls behind the animation.

Hyprland closes the request socket after every reply, which makes a QML
Socket log a warning per sample; one long-lived process keeps that quiet.
"""

import os
import select
import socket
import sys
import time

FAST_INTERVAL = 0.016  # while the pointer is moving
IDLE_INTERVAL = 0.05  # after it has been still for IDLE_AFTER seconds
IDLE_AFTER = 1.0


def socket_path():
    runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    signature = os.environ["HYPRLAND_INSTANCE_SIGNATURE"]
    return os.path.join(runtime, "hypr", signature, ".socket.sock")


def request(path, command):
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(1)
        connection.connect(path)
        connection.sendall(command.encode())
        chunks = []
        while chunk := connection.recv(4096):
            chunks.append(chunk)
    return b"".join(chunks).decode(errors="replace")


def main():
    path = socket_path()
    stdin = sys.stdin.fileno()
    pending = b""
    last_position = None
    last_move = 0.0
    next_poll = 0.0

    while True:
        now = time.monotonic()
        interval = FAST_INTERVAL if now - last_move < IDLE_AFTER else IDLE_INTERVAL
        ready, _, _ = select.select([stdin], [], [], max(0.0, next_poll - now))

        if ready:
            data = os.read(stdin, 4096)
            if not data:
                return  # The shell went away.
            pending += data
            *lines, pending = pending.split(b"\n")
            commands = [
                line.decode(errors="replace").strip()
                for line in lines
                if line.startswith(b"setcursor ")
            ]
            if commands:
                try:
                    request(path, "/" + commands[-1])
                except OSError:
                    pass
            continue

        next_poll = now + interval
        try:
            x, y = (int(value) for value in request(path, "/cursorpos").split(","))
        except (OSError, ValueError):
            continue

        if (x, y) != last_position:
            last_position = (x, y)
            last_move = now
            print(x, y, flush=True)


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        pass
