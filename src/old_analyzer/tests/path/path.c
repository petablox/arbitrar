#include <stdlib.h>

struct lock {
	int i;
};

static void mutex_lock(struct lock *l) {
	l->i = 1;
}

static void mutex_unlock(struct lock *l) {
	l->i = 0;
}

void run(int x, struct lock *l) {
  int *y = malloc(4);
  if (y != NULL)
    mutex_lock(l);
  if (y != NULL)
    mutex_unlock(l);
}
