#include <stdio.h>

int main() {
  FILE *f;
  f = fopen("a.c", "w");
  if (f == NULL) {
    return 1;
  }
  fputs("This is so good", f);
  fputs("\n", f);
  fputs("\n", f);
  fputs("\n", f);
  fclose(f);
}