#include <stdlib.h>

struct lock {
	int i;
};

struct foo {
  int x;
};

static void mutex_lock(struct lock *l) {
	l->i = 1;
}

static void mutex_unlock(struct lock *l) {
	l->i = 0;
}

void run(struct foo *a, struct lock *l) {
  int *b = malloc(0);
  if (a->x != 0)
    mutex_lock(l);
  if (a->x != 0)
    mutex_unlock(l);
}
