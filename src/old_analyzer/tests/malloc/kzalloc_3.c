#define unlikely(cond) (cond)
#define ext4_lblk_t int
#define ext4_fsblk_t int
#define NULL 0
#define EFSCORRUPTED 10000
#define ENOMEM 1000
#define GFP_NOFS 100

struct ext4_extent_header {
	short int	eh_magic;	/* probably will support different formats */
	short int	eh_entries;	/* number of valid entries */
	short int	eh_max;		/* capacity of store in entries */
	short int	eh_depth;	/* has tree real underlying blocks? */
	int	eh_generation;	/* generation of the tree */
};

struct buffer_head {

};

struct ext4_extent {
	int	ee_block;	/* first logical block extent covers */
	int	ee_len;		/* number of blocks covered by extent */
	int	ee_start_hi;	/* high 16 bits of physical block */
	int	ee_start_lo;	/* low 32 bits of physical block */
};

struct ext4_extent_idx {
	int	ei_block;	/* index covers logical blocks from 'block' */
	int	ei_leaf_lo;	/* pointer to the physical block of the next *
				 * level. leaf or next index could be there */
	short int	ei_leaf_hi;	/* high 16 bits of physical block */
	short int	ei_unused;
};

struct ext4_ext_path {
	ext4_fsblk_t			p_block;
	short int				p_depth;
	short int				p_maxdepth;
	struct ext4_extent		*p_ext;
	struct ext4_extent_idx		*p_idx;
	struct ext4_extent_header	*p_hdr;
	struct buffer_head		*p_bh;
};

struct inode {};

struct ext4_extent_header *ext_inode_hdr(struct inode *inode);

short int ext_depth(struct inode *inode);

void *kzalloc(int size, int gfp);

void kfree(void *);

struct ext4_ext_path *
ext4_find_extent(struct inode *inode, ext4_lblk_t block,
		 struct ext4_ext_path **orig_path, int flags)
{
	struct ext4_extent_header *eh;
	struct buffer_head *bh;
	struct ext4_ext_path *path = orig_path ? *orig_path : NULL;
	short int depth, i, ppos = 0;
	int ret;

	eh = ext_inode_hdr(inode);
	depth = ext_depth(inode);

	if (path) {
		ext4_ext_drop_refs(path);
		if (depth > path[0].p_maxdepth) {
			kfree(path);
			*orig_path = path = NULL;
		}
	}
	if (!path) {
		/* account possible depth increase */
		path = kzalloc(sizeof(struct ext4_ext_path) * (depth + 2),
				GFP_NOFS);
		if (unlikely(!path))
			return ERR_PTR(-ENOMEM);
		path[0].p_maxdepth = depth + 1;
	}
	path[0].p_hdr = eh;
	path[0].p_bh = NULL;

	i = depth;
	/* walk through the tree */
	while (i) {
		ext_debug("depth %d: num %d, max %d\n",
			  ppos, le16_to_cpu(eh->eh_entries), le16_to_cpu(eh->eh_max));

		ext4_ext_binsearch_idx(inode, path + ppos, block);
		path[ppos].p_block = ext4_idx_pblock(path[ppos].p_idx);
		path[ppos].p_depth = i;
		path[ppos].p_ext = NULL;

		bh = read_extent_tree_block(inode, path[ppos].p_block, --i,
					    flags);
		if (IS_ERR(bh)) {
			ret = PTR_ERR(bh);
			goto err;
		}

		eh = ext_block_hdr(bh);
		ppos++;
		if (unlikely(ppos > depth)) {
			put_bh(bh);
			EXT4_ERROR_INODE(inode,
					 "ppos %d > depth %d", ppos, depth);
			ret = -EFSCORRUPTED;
			goto err;
		}
		path[ppos].p_bh = bh;
		path[ppos].p_hdr = eh;
	}

	path[ppos].p_depth = i;
	path[ppos].p_ext = NULL;
	path[ppos].p_idx = NULL;

	/* find extent */
	ext4_ext_binsearch(inode, path + ppos, block);
	/* if not an empty leaf */
	if (path[ppos].p_ext)
		path[ppos].p_block = ext4_ext_pblock(path[ppos].p_ext);

	ext4_ext_show_path(inode, path);

	return path;

err:
	ext4_ext_drop_refs(path);
	kfree(path);
	if (orig_path)
		*orig_path = NULL;
	return ERR_PTR(ret);
}