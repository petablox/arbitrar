void do_something_else();
void *kzalloc(int size);

void *before() {
  for (int i = 0; i < 100; i++) {
    do_something_else();
  }
  void *ptr = kzalloc(30);
  if (!ptr) { return 0; }
  else { return ptr; }
}

void *after() {
  void *ptr = kzalloc(30);
  if (!ptr) { return 0; }
  for (int i = 0; i < 100; i++) {
    do_something_else();
  }
  return ptr;
}

int inside() {
  for (int i = 0; i < 100; i++) {
    do_something_else();
    void *ptr = kzalloc(30);
    if (!ptr) {
      return 0;
    }
  }
  return 100;
}