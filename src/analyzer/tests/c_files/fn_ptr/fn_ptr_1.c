long sum(long a, long b) {
    return a + b;
}

int sub(int a, int b) {
    return a - b;
}

int main() {
    int sub_res = sub(10, 20);
    int (*fn_ptr)(int, int) = &sum;
    int res = fn_ptr(sub_res, 5);
}