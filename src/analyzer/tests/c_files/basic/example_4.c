int z1() {
  printf("Hello world\n");
}

int y1() {
  z1();
}

int x1() {
  y1();
}

int x2() {
  y1();
}

int main() {
  x1();
  x2();
}