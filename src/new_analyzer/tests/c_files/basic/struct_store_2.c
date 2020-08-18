struct A {
  int i;
};

struct A *f(int i) {
  struct A *a = (struct A *) malloc(sizeof(struct A));
  a->i = i;
  return a;
}

int main() {
  struct A *a = f(10);
  return a->i;
}