struct Object {
  int a;
  int b;
  char c;
  char *d;
  char *e;
  struct Object *f;
  struct Object *g;
};

void run() {
  struct Object *ptr = malloc(sizeof(struct Object));
  if (!ptr) {
    return;
  }
  memset(ptr, 0, sizeof(struct Object));
  ptr->a = 3;
  ptr->b = 5;
}