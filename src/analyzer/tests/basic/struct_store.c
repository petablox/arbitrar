struct A {
  void *a;
};

int f(struct A* obj) {
  obj->a = malloc(8);
  if (obj->a == 0) {
    return 0;
  }
  return 1;
}

int main() {
  struct A obj = { a: 0 };
  f(&obj);
}