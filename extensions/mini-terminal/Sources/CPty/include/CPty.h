#ifndef CPTY_H
#define CPTY_H

#include <sys/types.h>

/// Starts `path` on a new pseudo-terminal that becomes the child's controlling terminal, so keyboard signals
/// (Ctrl-C, Ctrl-Z) and job control work. Returns the child's pid, or -1 on failure.
///
/// The parent also gets a handle on the slave side, and the child is held back until the parent has it:
/// macOS discards unread output when the last slave handle closes, so a fast-exiting child would otherwise
/// lose its output.
pid_t vn_spawn_pty(const char *path, char *const argv[], char *const envp[], const char *cwd,
                   unsigned short rows, unsigned short cols, int *master_out, int *slave_out);

#endif
