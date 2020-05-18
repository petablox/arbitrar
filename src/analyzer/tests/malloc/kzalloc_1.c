#define NULL 0
#define GFP_KERNEL 0
#define ENOMEM -1
#define INIT_HLIST_HEAD(e) {}
#define ERR_PTR(e) 0
#define _RET_IP_ 100
#define size_t int
#define gfp_t int

struct kmem_cache {
	int size;
};

extern void *__kmalloc_track_caller(size_t, gfp_t, unsigned long);
#define kmalloc_track_caller(size, flags) \
	__kmalloc_track_caller(size, flags, _RET_IP_)

static void *__do_kmalloc(size_t size, gfp_t flags, unsigned long caller) {
	struct kmem_cache *cachep;
	void *ret;

	cachep = kmalloc_slab(size, flags);
	if (unlikely(ZERO_OR_NULL_PTR(cachep)))
		return cachep;
	ret = slab_alloc(cachep, flags, caller);

	trace_kmalloc(caller, ret,
		      size, cachep->size, flags);

	return ret;
}

void *__kmalloc_track_caller(size_t size, gfp_t flags, unsigned long caller) {
	return __do_kmalloc(size, flags, caller);
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