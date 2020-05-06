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

static void mutex_lock(struct lock *l) {
	l->i = 1;
}

static void mutex_unlock(struct lock *l) {
	l->i = 0;
}

static struct drm_mode_object *idr_find(int crtc_idr, int id) {}

static struct drm_framebuffer *__drm_framebuffer_lookup(struct drm_device *dev, uint32_t id) {
	struct drm_mode_object *obj = NULL;
	struct drm_framebuffer *fb;

	mutex_lock(&dev->mode_config.idr_mutex);
	obj = idr_find(&dev->mode_config.crtc_idr, id);
	if (!obj || (obj->type != DRM_MODE_OBJECT_FB) || (obj->id != id))
		fb = NULL;
	else
		fb = obj_to_fb(obj);
	mutex_unlock(&dev->mode_config.idr_mutex);

	return fb;
}

/**
 * drm_framebuffer_lookup - look up a drm framebuffer and grab a reference
 * @dev: drm device
 * @id: id of the fb object
 *
 * If successful, this grabs an additional reference to the framebuffer -
 * callers need to make sure to eventually unreference the returned framebuffer
 * again, using @drm_framebuffer_unreference.
 */
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