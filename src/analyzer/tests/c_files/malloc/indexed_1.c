struct foo {
  int i;
  int *ptr;
};

void *kzalloc(int size);

int main() {
  struct foo foos[10];
  int i, num_elems = 100;

  // Ptr/i
  foos[5].ptr = kzalloc(sizeof(int) * num_elems);
  foos[5].i = num_elems;

  // Check ptr
  if (foos[5].ptr) {
    for (i = 0; i < num_elems; i++) {
      foos[5].ptr[i] = i;
    }

    return 0;
  }

  // Return
  return 1;
}