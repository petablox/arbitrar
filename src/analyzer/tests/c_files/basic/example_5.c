int *f(int x) {
  return malloc(x * sizeof(int));
}

int main() {
  int x = 1; // x has to be greater than 0
  int *z;
  z = f(x);
  if (z != 0) {
    z[0] = 10;
  }
}