void target(int *p) {
  *p = 1;
}

int main(int i) {
  target(&i);
  if (!i) {
    goto err;
  }

  i += 100;
  return 0;

err:
  return -1;
}