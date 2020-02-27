#include <stdio.h>

int main() {
  FILE *f;
  f = fopen("a.c", "w");
  if (f == NULL) {
    return 1;
  }
  fclose(f);
}