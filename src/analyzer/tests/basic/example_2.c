int sum(int a, int b) {
  return a + b;
}

void mutate(int *ptr, int idx, int val) {
  ptr[idx] = val;
}

int main() {
  int i = sum(3, 4);
  int j = sum(i, 5);
  int *p = (int *) malloc(i * j * sizeof(int));
  p[0] = 10;
  mutate(p, 2, 30);
}