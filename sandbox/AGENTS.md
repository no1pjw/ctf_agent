# Sandbox policy

This directory is the only permitted execution boundary for untrusted challenge artifacts.

- Copy artifacts here; never execute originals.
- Disable networking by default.
- Do not mount SSH keys, browser profiles, cloud credentials, home directories, or host sockets.
- Apply CPU, memory, process, file-size, and time limits.
- Use Docker as the default execution boundary for every challenge category.
- Use GDB only against processes running inside the Docker/sandbox boundary.
- Log the image/runtime version and exact command.
- Destroy disposable runtime state after preserving required evidence.
- Stop if containment cannot be verified.
