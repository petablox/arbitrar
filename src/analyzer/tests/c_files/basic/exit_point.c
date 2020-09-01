void err_new() {
  int *a = 0;
  if (a == 0)
    return;
  a[0] = 10;
}

int *some_function() {
  int i = 0;
  if (i == 0) {
    err_new();
  }
}

int main() {
  int *ptr = (int *) malloc(sizeof(int) * 4);
  int *dont_care = some_function();
  if (ptr != 0) {
    ptr[3] = 5;
  }
}