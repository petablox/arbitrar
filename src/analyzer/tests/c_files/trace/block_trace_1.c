int global;

void *malloc(int);

int f() {
  if (global) {
    void *a = malloc(3);
  } else {
    int i = 4;
  }
}

int g();

void main() {
  if (global) {
    f();
  } else {
    g();
  }
}