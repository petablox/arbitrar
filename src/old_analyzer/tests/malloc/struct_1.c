struct s {
  int *a;
  int *b;
};

void *malloc(int size);

void f() {
  struct s a;
  a.a = malloc(10);
  if (a.b) {
    a.b[10] = 10;
  }
}

void g() {
  struct s a;
  a.a = malloc(10);
  if (a.a) {
    a.a[10] = 10;
  }
}

int main() {
  f();
}