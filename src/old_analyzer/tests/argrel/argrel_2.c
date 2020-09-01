extern int g();

int f(int size) {
  char *p1 = malloc(size + 1);
  char *p2 = malloc(size);
  strcpy(p1, p2);
}

int main(int argc, char **argv) {
  int s = g();
  f(s);
}