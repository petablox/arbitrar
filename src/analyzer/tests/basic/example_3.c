int g(int x) {
  return x;
}

void *f(int z) {
  int y = g(z);
  return malloc(y * sizeof(int));
}

int h(int x) {
  return g(x);
}

int main() {
  f(0);
  h(1);
}