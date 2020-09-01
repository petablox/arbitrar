void *malloc(int i) {
  int j = 0;
  j += 10;
  return j;
}

int main() {
  void *ptr;
  int i = 1;
  if (i) {
    ptr = malloc(10);
    if (ptr) {
      i = 10;
    }
  }
}