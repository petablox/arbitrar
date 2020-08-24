int global;

void *malloc(int);

// 1. A D E
// 2. A E
// 3. A D F
// 4. A F
// 5. B D E
// 6. B E
// 7. B D F
// 8. B F

int f(int i) {
  if (i < 0) {
    int j = 5; // D
  }

  if (i) {
    void *a = malloc(3); // E
  } else {
    int i = 4; // F
  }
}

void main() {
  if (global) {
    f(5); // A
  } else {
    f(0); // B
  }
}