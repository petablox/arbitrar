#include <stdlib.h>
#include <string.h>

int f() {
  return 8;
}

int main() {
  int size = f();
  char *p1 = (char *)malloc(size + 1);
  char *p2 = (char *)malloc(2);
  strncpy(p1, p2, size);
  return 0;
}
