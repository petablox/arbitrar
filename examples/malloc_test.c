#include <stdlib.h>

int *y() {
  return (int *) malloc(10);
}

int x1() {
  int *data = y();
  data[0] = 10;
}

int x2() {
  int *data = y();
  if (data != 0) {
    data[0] = 10;
  }
}

int main() {
  x1();
  x2();
}