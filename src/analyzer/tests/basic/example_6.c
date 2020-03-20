// The goal of this example is to test if the target function itself will be included in the slice/trace
// The main function will call f, g, and h.
// When the target is (main -> g), then the slide should be [main, f, h], and the trace should be
// [call f, printf("call from f"), call g, call h, printf("call from h")]

int h() {
  printf("call from h");
}

int g() {
  printf("call from g");
}

int f() {
  printf("call from f");
}

int main() {
  f();
  g();
  h();
}