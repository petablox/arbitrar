int g(int *p) {
  if (p != 0) {
    p[0] = 10;
  }
}

int h(int *p) {
  p[1] = 20;
}

int f(int size) {
  void *p = (int *) malloc(size * sizeof(int));
  g(p);
  h(p);
}

int main() {
  int i = 0;
  int j = 10;
  f(i + j);
}