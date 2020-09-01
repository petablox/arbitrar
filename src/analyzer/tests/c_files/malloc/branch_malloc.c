int main() {
  int i = 0;
  void *ptr;
  if (i) {
    ptr = malloc(8);
  } else {
    ptr = 0;
  }
  return ptr;
}