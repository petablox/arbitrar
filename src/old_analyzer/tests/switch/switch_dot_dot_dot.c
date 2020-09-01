#define PT_LOPROC  0x70000000
#define PT_HIPROC  0x7fffffff

void kfree(void *);

int main() {
    int i = 34;
    i++;
    switch (i) {
        case PT_LOPROC ... PT_HIPROC:
            i += 10;
            break;
        default:
            return 1;
    }
    kfree(&i);
}