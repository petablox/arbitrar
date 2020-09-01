#include <stdlib.h>

struct lock {
	int i;
};

void *a;

static void mutex_lock(struct lock *l) {
	l->i = 1;
}

static void mutex_unlock(struct lock *l) {
	l->i = 0;
}

void run(int x, struct lock *l) {
  void *b = malloc(4);
  if (a != 0)
    mutex_lock(l);
  if (a != 0)
    mutex_unlock(l);
}
