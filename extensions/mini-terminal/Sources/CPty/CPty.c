#include "CPty.h"

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <string.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>
#include <util.h>

pid_t vn_spawn_pty(const char *path, char *const argv[], char *const envp[], const char *cwd,
                   unsigned short rows, unsigned short cols, int *master_out, int *slave_out) {
    int gate[2];
    if (pipe(gate) != 0) return -1;

    struct winsize size;
    memset(&size, 0, sizeof size);
    size.ws_row = rows;
    size.ws_col = cols;

    int master = -1;
    char name[128];
    pid_t pid = forkpty(&master, name, NULL, &size);
    if (pid < 0) {
        close(gate[0]);
        close(gate[1]);
        return -1;
    }

    if (pid == 0) {
        // Child: only async-signal-safe calls from here to exec.
        close(gate[1]);
        char byte;
        while (read(gate[0], &byte, 1) < 0 && errno == EINTR) {}
        if (cwd != NULL) { if (chdir(cwd) != 0) { /* keep the default directory */ } }
        sigset_t none;
        sigemptyset(&none);
        sigprocmask(SIG_SETMASK, &none, NULL);
        for (int sig = 1; sig < NSIG; sig++) {
            if (sig != SIGKILL && sig != SIGSTOP) signal(sig, SIG_DFL);
        }
        int limit = getdtablesize();
        for (int fd = 3; fd < limit; fd++) close(fd);
        execve(path, argv, envp);
        _exit(127);
    }

    // Parent.
    close(gate[0]);
    int slave = open(name, O_RDWR | O_NOCTTY);
    fcntl(master, F_SETFD, FD_CLOEXEC);
    fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK);
    if (slave >= 0) fcntl(slave, F_SETFD, FD_CLOEXEC);
    char go = 1;
    while (write(gate[1], &go, 1) < 0 && errno == EINTR) {}
    close(gate[1]);

    *master_out = master;
    *slave_out = slave;
    return pid;
}
