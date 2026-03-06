#!/usr/bin/env python3

import os
import pty
import select
import sys
import time


PROMPT_TIMEOUT = float(os.environ.get("LACY_PTY_PROMPT_TIMEOUT", "20"))
QUERY_TIMEOUT = float(os.environ.get("LACY_PTY_QUERY_TIMEOUT", "60"))
QUERY = os.environ.get("LACY_PTY_QUERY", "inspect @README.md and @lib/core")
REPO_DIR = os.environ.get("LACY_PTY_REPO")
HOME_DIR = os.environ.get("LACY_PTY_HOME")

if not REPO_DIR or not HOME_DIR:
    print("Missing LACY_PTY_REPO or LACY_PTY_HOME", file=sys.stderr)
    sys.exit(1)


def read_until(fd, needle, timeout):
    deadline = time.time() + timeout
    chunks = []
    while time.time() < deadline:
        ready, _, _ = select.select([fd], [], [], 0.2)
        if fd not in ready:
            continue
        data = os.read(fd, 65536)
        if not data:
            break
        text = data.decode("utf-8", errors="replace")
        chunks.append(text)
        if needle in "".join(chunks):
            return "".join(chunks)
    raise TimeoutError(f"Timed out waiting for {needle!r}")


pid, fd = pty.fork()
if pid == 0:
    env = os.environ.copy()
    env["HOME"] = HOME_DIR
    env["ZDOTDIR"] = HOME_DIR
    env["LACY_SHELL_HOME"] = os.path.join(HOME_DIR, ".lacy")
    env["LACY_AUTO_START"] = "true"
    os.execvpe("zsh", ["zsh", "-i"], env)

transcript = []

try:
    transcript.append(read_until(fd, "▌", PROMPT_TIMEOUT))
    os.write(fd, (QUERY + "\n").encode())
    transcript.append(read_until(fd, "☑ fake agent ready", QUERY_TIMEOUT))
    transcript.append(read_until(fd, "Original query:", QUERY_TIMEOUT))
    transcript.append(read_until(fd, QUERY, QUERY_TIMEOUT))
except TimeoutError as exc:
    print("".join(transcript), end="")
    print(str(exc), file=sys.stderr)
    sys.exit(1)
finally:
    try:
        os.kill(pid, 15)
    except OSError:
        pass
    time.sleep(0.5)
    try:
        ready, _, _ = select.select([fd], [], [], 0.2)
        if fd in ready:
            transcript.append(os.read(fd, 65536).decode("utf-8", errors="replace"))
    except OSError:
        pass

output = "".join(transcript)
print(output, end="")

required = [
    "Thinking",
    "☐ inspect request",
    "☑ fake agent ready",
    "@README.md",
    "@lib/core",
    "Original query:",
]

for needle in required:
    if needle not in output:
        print(f"Missing expected output: {needle}", file=sys.stderr)
        sys.exit(1)
