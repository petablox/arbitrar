#include <stdlib.h>

void my_free(void *ptr) {
  ptr = 0;
}

void free_wrapper(void *ptr) {
  my_free(ptr);
}

void f() {
  int *ptr = (int *) malloc(10);
  ptr[3] = 30;
  ptr[9] = 90;
  free_wrapper(ptr);
}

void g() {
  int *ptr = (int *) malloc(10);
  ptr[3] = 30;
  ptr[9] = 90;
  if (ptr != NULL) {
    free_wrapper(ptr);
  }
}