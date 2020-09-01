void kzalloc();
void kfree();
void krealloc();

void z() {
    z();
}

void x() {
    z();
}

void y() {
    z();
}

void c() {
    krealloc();
}

void d() {
    x();
    kzalloc();
    kfree();
}

void b() {
    c();
    d();
}

void a() {
    b();
}