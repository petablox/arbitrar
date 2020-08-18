char *g(int i, char *str) {
  char *another = (char *) malloc(i * sizeof(char) + 1);
  for (int j = 0; j < i; j++) {
    another[j] = str[j];
  }
  return another;
}

int f(int i) {
  char *str = "something";
  char *another = g(i, str);
  if (another) {
    printf("%s", another);
  }
}