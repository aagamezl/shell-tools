2) Summary of main faults (tl;dr)

You spawn nc multiple times per request. Each nc call creates its own listener/connection — you must read request method and path from the same connection.

You’re mixing up connection lifecycle — reading request with one nc, replying with a different nc. That breaks the HTTP conversation.

FIFOs are tricky: naive FIFO usage leads to blocking/deadlock unless you open the ends in the correct order or use O_RDWR style openings or coproc.

Syntax errors: tmpfifo=$(mktemp -u) mkfifo "$tmpfifo" has missing semicolon; process substitution use is broken.

Improper HTTP replies: no Content-Length, wrong line endings — browsers tolerate it sometimes, but it’s not correct.

Race conditions & security: mktemp -u is insecure.