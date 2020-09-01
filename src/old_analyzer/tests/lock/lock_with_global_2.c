struct mutex {
    int something;
    int flag;
};

struct mutex global_lock;

void mutex_lock(struct mutex *lock) {
    lock->flag = 1;
}

void mutex_unlock(struct mutex *lock) {
    lock->flag = 1;
}

int main() {
    if (global_lock.something) {
        mutex_lock(&global_lock);
    }

    int i = 0;
    for (i = 0; i < 10; i++) {
        printf("%d", i);
    }

    if (global_lock.something) {
        mutex_unlock(&global_lock);
    }
}