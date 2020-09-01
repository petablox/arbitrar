void *malloc(int size);
int *kzalloc(int size);

struct Object {
  int *ptr;
};

// Dereferenced + not Returned
void deref_1() {
  int *ptr = kzalloc(10);
  ptr[10] = 5;
}

// Not derefed + Returned
int *deref_2() {
  int *ptr = kzalloc(10);
  return ptr;
}

// Not derefed + indirectly returned
struct Object *deref_3() {
  struct Object *o = (struct Object *) malloc(sizeof(struct Object));
  o->ptr = kzalloc(10);
  return o;
}

// Derefed + indirectly returned
struct Object *deref_4() {
  struct Object *o = (struct Object *) malloc(sizeof(struct Object));
  o->ptr = kzalloc(10);
  o->ptr[10] = 100;
  return o;
}