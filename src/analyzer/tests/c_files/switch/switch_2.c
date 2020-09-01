void *malloc(int i) {
  int j = 0;
  j += 10;
  return j;
}

int main() {
  void *ptr, *ptr2;
  int i = 100;
  switch (i) {
    case 1: ptr = malloc(10); break;
    case 2: ptr = malloc(20); break;
    case 100: i = 30; break;
    default: i = 40;
  }
  ptr2 = malloc(i);
  return 10;
}