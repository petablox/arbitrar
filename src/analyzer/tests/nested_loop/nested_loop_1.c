void mutex_lock(int *lock);
void mutex_unlock(int *unlock);

int main() {
    int sum = 0;
    int lock = 0;
    mutex_lock(&lock);
    for (int i = 0; i < 10; i++) {
        for (int j = 0; j < 30; j++) {
            sum += i + j;
        }
    }
    mutex_unlock(&lock);
}