#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
    (void)argc;
    if (strstr(argv[0], "Hang")) { for (;;) pause(); }
    if (strstr(argv[0], "Invalid")) puts("{\"version\":1,\"status\":\"fresh\",\"percent\":101}");
    else puts("{\"version\":1,\"status\":\"fresh\",\"percent\":19}");
    return 0;
}
