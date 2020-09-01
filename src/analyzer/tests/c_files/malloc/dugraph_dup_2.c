int main() {
  int i = 0;
  if (i == 10) {
    int j = 1;
  } else {
    int k = 2;
  }
  int *ptr = (int *) malloc(4 * sizeof(int));
  if (i == 20) {
    ptr[0] = 20;
  } else {
    ptr[1] = 21;
  }
}