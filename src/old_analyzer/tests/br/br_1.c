void target(int *p) {
  *p = 1;
}

int main() {
  int i = 0;
  target(&i);
  if (!i) {
    goto err;
  }

  i += 100;
  return 0;

err:
  return -1;
}