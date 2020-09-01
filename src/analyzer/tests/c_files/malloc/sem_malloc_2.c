int main() {
  char *p1 = (char *) malloc(sizeof(char) * 10);
  char *p2 = (char *) malloc(sizeof(char) * 10);

  // p1 is checked
  if (p1 != 0) {
    p1[0] = 10;
  }

  // p2 is not
  p2[0] = 10;
}