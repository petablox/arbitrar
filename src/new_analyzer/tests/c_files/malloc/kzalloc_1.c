#define NULL 0
#define GFP_KERNEL 0
#define ENOMEM -1
#define INIT_HLIST_HEAD(e) {}
#define ERR_PTR(e) 0
#define _RET_IP_ 100
#define KMALLOC_MAX_CACHE_SIZE 1000
#define size_t int
#define gfp_t int

struct kmem_cache {
	int size;
};

extern void *__kmalloc_track_caller(size_t, gfp_t, unsigned long);
#define kmalloc_track_caller(size, flags) \
	__kmalloc_track_caller(size, flags, _RET_IP_)

void *__kmalloc_track_caller(size_t size, gfp_t gfpflags, unsigned long caller) {
	struct kmem_cache *s;
	void *ret;

	if (unlikely(size > KMALLOC_MAX_CACHE_SIZE))
		return kmalloc_large(size, gfpflags);

	s = kmalloc_slab(size, gfpflags);

	if (unlikely(ZERO_OR_NULL_PTR(s)))
		return s;

	ret = slab_alloc(s, gfpflags, caller);

	/* Honor the call site pointer we received. */
	trace_kmalloc(caller, ret, size, s->size, gfpflags);

	return ret;
}

void memcpy(void *p, void* src, int len);

void *kmemdup(void *src, int len, int gfp) {
	void *p;
	p = kmalloc_track_caller(len, gfp);
	if (p)
		memcpy(p, src, len);
	return p;
}

void *kzalloc(int size, int type);

void kfree(void *);

struct hlist_head {};

struct net {};

struct cache_detail {
	struct hlist_head **hash_table;
  int hash_size;
  struct net *net;
};

struct cache_detail *cache_create_net(struct cache_detail *tmpl, struct net *net) {
	struct cache_detail *cd;
	int i;

	cd = kmemdup(tmpl, sizeof(struct cache_detail), GFP_KERNEL);
	if (cd == NULL)
		return ERR_PTR(-ENOMEM);

	cd->hash_table = kzalloc(cd->hash_size * sizeof(struct hlist_head), GFP_KERNEL);
	if (cd->hash_table == NULL) {
		kfree(cd);
		return ERR_PTR(-ENOMEM);
	}

	for (i = 0; i < cd->hash_size; i++)
		INIT_HLIST_HEAD(&cd->hash_table[i]);
	cd->net = net;
	return cd;
}