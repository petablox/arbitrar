int main() {
  int i = 0;
  if (i == 10) {
    int j = 1;
  } else {
    int k = 2;
  }
  int *ptr = (int *) malloc(4 * sizeof(int));
  if (i == 20) {
    int j = 21;
  } else {
    int k = 22;
  }
  ptr[10] = 20;
}