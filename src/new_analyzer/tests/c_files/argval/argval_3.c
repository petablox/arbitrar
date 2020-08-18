int free(int s) {
  return s;
}

int g(int i, int j) {
  return free(i + j);
}

int f(int i) {
  int j = g(i, 3);
  return j;
}