char *new() {
  return (char *) malloc(sizeof(char) * 10);
}

int main() {
  char *p1 = new();
  char *p2 = new();
  if (p1 != 0) {
    p1[0] = 10;
  }
}