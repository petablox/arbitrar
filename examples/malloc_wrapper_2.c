#include <stdlib.h>

int *malloc_wrapper() {
  return (int *) malloc(8);
}

int main() {
  int i = 0;
}