// driver/gpu/drm/drm_ctrc.c

#define NULL 0
#define uint32_t int
#define DRM_MODE_OBJECT_FB 10

struct lock {
	int i;
};

struct config {
	struct lock idr_mutex;
	struct lock fb_lock;
	int crtc_idr;
};

struct drm_device {
	struct config mode_config;
};

struct drm_framebuffer {
	int refcount;
};

struct drm_mode_object {
	int type;
	int id;
};

static void mutex_lock(struct lock *l);

static void mutex_unlock(struct lock *l);

static struct drm_mode_object *idr_find(int crtc_idr, int id);

static struct drm_framebuffer *__drm_framebuffer_lookup(struct drm_device *dev, uint32_t id);

struct drm_framebuffer *drm_framebuffer_lookup(struct drm_device *dev, uint32_t id) {
	struct drm_framebuffer *fb;

	mutex_lock(&dev->mode_config.fb_lock);
	fb = __drm_framebuffer_lookup(dev, id);
	if (fb) {
		if (!kref_get_unless_zero(&fb->refcount))
			fb = NULL;
	}
	mutex_unlock(&dev->mode_config.fb_lock);

	return fb;
}