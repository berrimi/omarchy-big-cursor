#!/usr/bin/env python3
"""I/O bridge between the Big Cursor service and Hyprland's request socket.

stdout: "<x> <y>" each time the pointer moves.
stdin:  "cursor hide" / "cursor show" lines, which hide or show the real
        compositor cursor while the service draws the enlarged one.

Hyprland closes the request socket after every reply, which makes a QML
Socket log a warning per sample; one long-lived process keeps that quiet.
If the shell exits while the cursor is hidden, the bridge shows it again.
"""

import os
import select
import socket
import sys
import time

FAST_INTERVAL = 0.008  # while the pointer is moving
IDLE_INTERVAL = 0.05  # after it has been still for IDLE_AFTER seconds
IDLE_AFTER = 1.0

COMMANDS = {
    "cursor hide": "/eval hl.config({ cursor = { invisible = true } })",
    "cursor show": "/eval hl.config({ cursor = { invisible = false } })",
}


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
    hidden = False
    last_position = None
    last_move = 0.0
    next_poll = 0.0

    try:
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
                commands = [line.decode(errors="replace").strip() for line in lines]
                commands = [command for command in commands if command in COMMANDS]
                # Only the newest state matters when several arrive at once.
                if commands:
                    try:
                        request(path, COMMANDS[commands[-1]])
                        hidden = commands[-1] == "cursor hide"
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
    finally:
        if hidden:
            try:
                request(path, COMMANDS["cursor show"])
            except OSError:
                pass


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        pass
