#include <stdlib.h>

char *f(int x) {
  char *p = (char *)malloc(4 * x);
  return p;
}

int main() {
  int x = 0;
  char *p = f(x);
  if (!p)
    *p = 1;
  return 0;
}
