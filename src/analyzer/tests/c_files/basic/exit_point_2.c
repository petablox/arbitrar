void some_function() {
  int *a = 0;
  if (a == 0)
    return;
  a[0] = 10;
}

int main() {
  int *ptr = (int *) malloc(sizeof(int) * 4);
  some_function();
  if (ptr != 0) {
    ptr[3] = 5;
  }
}