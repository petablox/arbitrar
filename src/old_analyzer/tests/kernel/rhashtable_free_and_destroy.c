#define NULL 0
#define bool char

struct mutex {
    int i;
};

struct rhash_head {
    struct rhash_head *next;
};

struct bucket_table {
    struct bucket_table *future_tbl;
    int size;
};

struct rhashtable {
    struct bucket_table *tbl;
    struct mutex mutex;
    int run_work;
};

void mutex_lock(struct mutex *lock);
void mutex_unlock(struct mutex *lock);
void cancel_work_sync(int *work);
void *rht_dereference(void *ptr, struct rhashtable *ht);
void cond_resched();
bool rht_is_a_nulls(struct rhash_head *head);
struct bucket_table *rht_bucket(struct bucket_table *tbl, int i);
void *rht_ptr_exclusive(void *ptr);
void rhashtable_free_one(struct rhashtable *ht, struct rhash_head *hd, void (*free_fn)(void *ptr, void *arg), void *arg);
void bucket_table_free(struct bucket_table *bkt);

void rhashtable_free_and_destroy(struct rhashtable *ht, void (*free_fn)(void *ptr, void *arg), void *arg) {
    struct bucket_table *tbl, *next_tbl;
    unsigned int i;

    cancel_work_sync(&ht->run_work);
    
    mutex_lock(&ht->mutex);
    tbl = rht_dereference(ht->tbl, ht);

restart:
    if (free_fn) {
        for (i = 0; i < tbl->size; i++) {
            struct rhash_head *pos, *next;
            cond_resched();
            for (pos = rht_ptr_exclusive(rht_bucket(tbl, i)),
                 next = !rht_is_a_nulls(pos) ?
                    rht_dereference(pos->next, ht) : NULL;
                 !rht_is_a_nulls(pos);
                 pos = next,
                 next = !rht_is_a_nulls(pos) ?
                    rht_dereference(pos->next, ht) : NULL) {
                
                rhashtable_free_one(ht, pos, free_fn, arg);
            }
        }
    }

    next_tbl = rht_dereference(tbl->future_tbl, ht);
    bucket_table_free(tbl);

    mutex_unlock(&ht->mutex);
}