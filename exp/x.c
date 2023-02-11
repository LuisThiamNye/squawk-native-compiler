#include <setjmp.h>
#include <signal.h>
#include <stdio.h>

jmp_buf buf;

void segfault_handler(int sig) {
  printf("Caught signal %d\n", sig);
  longjmp(buf, 1);
}

int main() {
  if (signal(SIGSEGV, segfault_handler) == SIG_ERR) {
    printf("Error setting up signal handler\n");
    return 1;
  }

  if (setjmp(buf) != 0) {
    printf("Recovered from segmentation fault\n");
    return 0;
  }

  // Code that may cause a segmentation fault
  int* ptr = NULL;
  *ptr = 42;

  return 0;
}