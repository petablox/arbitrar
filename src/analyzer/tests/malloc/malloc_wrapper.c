#include <stdlib.h>

int *malloc_wrapper() {
  return (int *) malloc(8);
}

void f() {
  int *ptr = malloc_wrapper();
  if (ptr != 0) {
    ptr[5] = 10;
  }
}

int main() {
  f();
}