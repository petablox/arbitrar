int global;

void *malloc(int);

int f(int i) {

  if (i < 0) {
    int j = 5;
  }

  if (i) {
    void *a = malloc(3);
  } else {
    int i = 4;
  }
}

void main() {
  if (global) {
    f(5);
  } else {
    f(0);
  }
}