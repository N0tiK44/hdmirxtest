#define _GNU_SOURCE

#include <drm.h>
#include <drm_fourcc.h>
#include <errno.h>
#include <fcntl.h>
#include <getopt.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <xf86drm.h>
#include <xf86drmMode.h>

static volatile sig_atomic_t stopped;

static void on_signal(int signal_number)
{
    (void)signal_number;
    stopped = 1;
}

static double refresh_hz(const drmModeModeInfo *m)
{
    if (!m->htotal || !m->vtotal)
        return 0.0;
    double value = (double)m->clock * 1000.0 / (double)m->htotal /
        (double)m->vtotal;
    if (m->flags & DRM_MODE_FLAG_INTERLACE)
        value *= 2.0;
    if (m->flags & DRM_MODE_FLAG_DBLSCAN)
        value /= 2.0;
    if (m->vscan > 1)
        value /= (double)m->vscan;
    return value;
}

static bool is_hdmi(const drmModeConnector *connector)
{
    return connector->connector_type == DRM_MODE_CONNECTOR_HDMIA ||
        connector->connector_type == DRM_MODE_CONNECTOR_HDMIB;
}

static drmModeConnector *find_hdmi_connector(int fd, drmModeRes *resources)
{
    for (int i = 0; i < resources->count_connectors; i++) {
        drmModeConnector *connector = drmModeGetConnector(
            fd, resources->connectors[i]);
        if (!connector)
            continue;
        if (is_hdmi(connector) &&
            connector->connection == DRM_MODE_CONNECTED &&
            connector->count_modes > 0)
            return connector;
        drmModeFreeConnector(connector);
    }
    return NULL;
}

static int crtc_index(drmModeRes *resources, uint32_t crtc_id)
{
    for (int i = 0; i < resources->count_crtcs; i++)
        if (resources->crtcs[i] == crtc_id)
            return i;
    return -1;
}

static uint32_t find_crtc(int fd, drmModeRes *resources,
    drmModeConnector *connector)
{
    if (connector->encoder_id) {
        drmModeEncoder *encoder = drmModeGetEncoder(fd, connector->encoder_id);
        if (encoder) {
            uint32_t current = encoder->crtc_id;
            drmModeFreeEncoder(encoder);
            if (current)
                return current;
        }
    }

    for (int i = 0; i < connector->count_encoders; i++) {
        drmModeEncoder *encoder = drmModeGetEncoder(fd, connector->encoders[i]);
        if (!encoder)
            continue;
        for (int c = 0; c < resources->count_crtcs; c++) {
            if (encoder->possible_crtcs & (1u << c)) {
                uint32_t id = resources->crtcs[c];
                drmModeFreeEncoder(encoder);
                return id;
            }
        }
        drmModeFreeEncoder(encoder);
    }
    return 0;
}

static bool plane_has_format(const drmModePlane *plane, uint32_t format)
{
    for (uint32_t i = 0; i < plane->count_formats; i++)
        if (plane->formats[i] == format)
            return true;
    return false;
}

static uint64_t plane_type(int fd, uint32_t plane_id)
{
    drmModeObjectProperties *properties = drmModeObjectGetProperties(
        fd, plane_id, DRM_MODE_OBJECT_PLANE);
    if (!properties)
        return UINT64_MAX;
    uint64_t type = UINT64_MAX;
    for (uint32_t i = 0; i < properties->count_props; i++) {
        drmModePropertyRes *property = drmModeGetProperty(fd,
            properties->props[i]);
        if (property) {
            if (strcmp(property->name, "type") == 0)
                type = properties->prop_values[i];
            drmModeFreeProperty(property);
        }
    }
    drmModeFreeObjectProperties(properties);
    return type;
}

static uint32_t find_primary_plane(int fd, int wanted_crtc)
{
    drmModePlaneRes *planes = drmModeGetPlaneResources(fd);
    if (!planes)
        return 0;
    uint32_t answer = 0;
    for (uint32_t i = 0; i < planes->count_planes; i++) {
        drmModePlane *plane = drmModeGetPlane(fd, planes->planes[i]);
        if (!plane)
            continue;
        if ((plane->possible_crtcs & (1u << wanted_crtc)) &&
            plane_has_format(plane, DRM_FORMAT_XRGB8888) &&
            plane_type(fd, plane->plane_id) == DRM_PLANE_TYPE_PRIMARY)
            answer = plane->plane_id;
        drmModeFreePlane(plane);
        if (answer)
            break;
    }
    drmModeFreePlaneResources(planes);
    return answer;
}

static bool find_pipeline(int fd, drmModeRes *resources,
    drmModeConnector *connector, uint32_t *crtc_id, int *wanted_crtc,
    uint32_t *primary_plane)
{
    *crtc_id = find_crtc(fd, resources, connector);
    *wanted_crtc = crtc_index(resources, *crtc_id);
    *primary_plane = *wanted_crtc >= 0 ?
        find_primary_plane(fd, *wanted_crtc) : 0;
    if (*primary_plane)
        return true;

    /* The connector's current encoder can reference a pipeline that cannot
     * scan out our dumb XRGB8888 buffer. Try every encoder/CRTC routing that
     * the kernel advertises before declaring the display unusable. */
    for (int i = 0; i < connector->count_encoders; i++) {
        drmModeEncoder *encoder = drmModeGetEncoder(fd, connector->encoders[i]);
        if (!encoder)
            continue;
        for (int c = 0; c < resources->count_crtcs; c++) {
            if (!(encoder->possible_crtcs & (1u << c)))
                continue;
            uint32_t plane = find_primary_plane(fd, c);
            if (plane) {
                *crtc_id = resources->crtcs[c];
                *wanted_crtc = c;
                *primary_plane = plane;
                drmModeFreeEncoder(encoder);
                return true;
            }
        }
        drmModeFreeEncoder(encoder);
    }
    return false;
}

static int mode_score(const drmModeModeInfo *mode)
{
    if ((mode->flags & (DRM_MODE_FLAG_INTERLACE | DRM_MODE_FLAG_DBLSCAN)) ||
        mode->hdisplay > 3840 || mode->vdisplay > 2160 || mode->clock > 600000)
        return 1000;
    double hz = refresh_hz(mode);
    if (mode->hdisplay == 1920 && mode->vdisplay == 1080 &&
        hz >= 59.0 && hz <= 61.0)
        return 0;
    if (mode->hdisplay == 1920 && mode->vdisplay == 1080 &&
        hz >= 49.0 && hz <= 51.0)
        return 1;
    if (mode->hdisplay == 1280 && mode->vdisplay == 720 &&
        hz >= 59.0 && hz <= 61.0)
        return 2;
    if (mode->hdisplay == 1280 && mode->vdisplay == 720 &&
        hz >= 49.0 && hz <= 51.0)
        return 3;
    if (mode->type & DRM_MODE_TYPE_PREFERRED)
        return 10;
    return 100;
}

static bool mode_matches_profile(const drmModeModeInfo *mode,
    const char *profile)
{
    double hz = refresh_hz(mode);
    if (strcmp(profile, "1080p60") == 0)
        return mode->hdisplay == 1920 && mode->vdisplay == 1080 &&
            hz >= 59.0 && hz <= 61.0;
    if (strcmp(profile, "1080p50") == 0)
        return mode->hdisplay == 1920 && mode->vdisplay == 1080 &&
            hz >= 49.0 && hz <= 51.0;
    if (strcmp(profile, "720p60") == 0)
        return mode->hdisplay == 1280 && mode->vdisplay == 720 &&
            hz >= 59.0 && hz <= 61.0;
    if (strcmp(profile, "720p50") == 0)
        return mode->hdisplay == 1280 && mode->vdisplay == 720 &&
            hz >= 49.0 && hz <= 51.0;
    if (strcmp(profile, "preferred") == 0)
        return (mode->type & DRM_MODE_TYPE_PREFERRED) != 0;
    return false;
}

static drmModeModeInfo *choose_mode(drmModeConnector *connector,
    const char *profile)
{
    drmModeModeInfo *best = NULL;
    int best_score = 1000;
    for (int i = 0; i < connector->count_modes; i++) {
        if (profile && strcmp(profile, "auto") != 0) {
            if (mode_score(&connector->modes[i]) < 1000 &&
                mode_matches_profile(&connector->modes[i], profile))
                return &connector->modes[i];
            continue;
        }
        int score = mode_score(&connector->modes[i]);
        if (score < best_score) {
            best_score = score;
            best = &connector->modes[i];
        }
    }
    return best;
}

static int save_edid(int fd, drmModeConnector *connector, const char *path)
{
    if (!path)
        return 0;
    drmModeObjectProperties *properties = drmModeObjectGetProperties(fd,
        connector->connector_id, DRM_MODE_OBJECT_CONNECTOR);
    if (!properties)
        return -1;
    int result = -1;
    for (uint32_t i = 0; i < properties->count_props; i++) {
        drmModePropertyRes *property = drmModeGetProperty(fd,
            properties->props[i]);
        if (!property)
            continue;
        if (strcmp(property->name, "EDID") == 0 && properties->prop_values[i]) {
            drmModePropertyBlobRes *blob = drmModeGetPropertyBlob(fd,
                properties->prop_values[i]);
            if (blob) {
                FILE *stream = fopen(path, "wb");
                if (stream) {
                    result = fwrite(blob->data, 1, blob->length, stream) ==
                        blob->length ? 0 : -1;
                    fclose(stream);
                }
                drmModeFreePropertyBlob(blob);
            }
        }
        drmModeFreeProperty(property);
        if (result == 0)
            break;
    }
    drmModeFreeObjectProperties(properties);
    return result;
}

struct framebuffer {
    uint32_t handle;
    uint32_t pitch;
    uint64_t size;
    uint32_t id;
    uint32_t *pixels;
};

static int create_framebuffer(int fd, uint32_t width, uint32_t height,
    struct framebuffer *fb)
{
    struct drm_mode_create_dumb create = {0};
    create.width = width;
    create.height = height;
    create.bpp = 32;
    if (ioctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &create) < 0)
        return -1;
    fb->handle = create.handle;
    fb->pitch = create.pitch;
    fb->size = create.size;
    uint32_t handles[4] = {fb->handle, 0, 0, 0};
    uint32_t pitches[4] = {fb->pitch, 0, 0, 0};
    uint32_t offsets[4] = {0, 0, 0, 0};
    if (drmModeAddFB2(fd, width, height, DRM_FORMAT_XRGB8888,
        handles, pitches, offsets, &fb->id, 0) != 0)
        return -1;
    struct drm_mode_map_dumb map = {0};
    map.handle = fb->handle;
    if (ioctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &map) < 0)
        return -1;
    fb->pixels = mmap(NULL, fb->size, PROT_READ | PROT_WRITE, MAP_SHARED,
        fd, map.offset);
    return fb->pixels == MAP_FAILED ? -1 : 0;
}

static void destroy_framebuffer(int fd, struct framebuffer *fb)
{
    if (fb->pixels && fb->pixels != MAP_FAILED)
        munmap(fb->pixels, fb->size);
    if (fb->id)
        drmModeRmFB(fd, fb->id);
    if (fb->handle) {
        struct drm_mode_destroy_dumb destroy = {0};
        destroy.handle = fb->handle;
        ioctl(fd, DRM_IOCTL_MODE_DESTROY_DUMB, &destroy);
    }
}

static void draw_pattern(struct framebuffer *fb, uint32_t width,
    uint32_t height, unsigned phase)
{
    static const uint32_t colours[] = {
        0x00ffffff, 0x00ffff00, 0x0000ffff, 0x0000ff00,
        0x00ff00ff, 0x00ff0000, 0x000000ff, 0x00101010
    };
    for (uint32_t y = 0; y < height; y++) {
        uint32_t *row = (uint32_t *)((uint8_t *)fb->pixels + y * fb->pitch);
        for (uint32_t x = 0; x < width; x++) {
            unsigned bar = (unsigned)(((uint64_t)x * 8) / width);
            row[x] = colours[bar];
            if (y < height / 24 || y >= height - height / 24)
                row[x] = ((x / 32 + phase) & 1) ? 0x00ffffff : 0x00000000;
        }
    }
    uint32_t box = width / 12;
    uint32_t left = (phase * (box ? box : 1)) % (width ? width : 1);
    for (uint32_t y = height / 2; y < height / 2 + height / 10 && y < height; y++) {
        uint32_t *row = (uint32_t *)((uint8_t *)fb->pixels + y * fb->pitch);
        for (uint32_t x = left; x < left + box && x < width; x++)
            row[x] = 0x00ffffff;
    }
}

static bool connector_still_present(int fd, uint32_t connector_id)
{
    drmModeConnector *connector = drmModeGetConnector(fd, connector_id);
    if (!connector)
        return false;
    bool present = connector->connection == DRM_MODE_CONNECTED;
    drmModeFreeConnector(connector);
    return present;
}

static void usage(const char *program)
{
    fprintf(stderr, "Usage: %s [--card /dev/dri/card0] [--seconds 120] "
        "[--edid-output FILE] [--profile auto|1080p60|720p60|1080p50|720p50|preferred]\n",
        program);
}

int main(int argc, char **argv)
{
    const char *card = "/dev/dri/card0";
    const char *edid_output = NULL;
    const char *profile = "auto";
    unsigned seconds = 120;
    static const struct option options[] = {
        {"card", required_argument, NULL, 'c'},
        {"seconds", required_argument, NULL, 's'},
        {"edid-output", required_argument, NULL, 'e'},
        {"profile", required_argument, NULL, 'p'},
        {"help", no_argument, NULL, 'h'},
        {NULL, 0, NULL, 0}
    };
    int option;
    while ((option = getopt_long(argc, argv, "c:s:e:p:h", options, NULL)) != -1) {
        switch (option) {
        case 'c': card = optarg; break;
        case 's': seconds = (unsigned)strtoul(optarg, NULL, 10); break;
        case 'e': edid_output = optarg; break;
        case 'p': profile = optarg; break;
        default: usage(argv[0]); return option == 'h' ? 0 : 2;
        }
    }

    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);
    int fd = open(card, O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        fprintf(stderr, "Cannot open %s: %s\n", card, strerror(errno));
        return 1;
    }
    drmSetClientCap(fd, DRM_CLIENT_CAP_UNIVERSAL_PLANES, 1);
    drmModeRes *resources = drmModeGetResources(fd);
    if (!resources) {
        fprintf(stderr, "Cannot read DRM resources: %s\n", strerror(errno));
        close(fd);
        return 1;
    }
    drmModeConnector *connector = find_hdmi_connector(fd, resources);
    if (!connector) {
        fprintf(stderr, "No connected HDMI-TX display with EDID modes was found.\n");
        drmModeFreeResources(resources);
        close(fd);
        return 75;
    }
    drmModeModeInfo *mode = choose_mode(connector, profile);
    uint32_t crtc_id = 0;
    uint32_t primary_plane = 0;
    int wanted_crtc = -1;
    bool pipeline_found = find_pipeline(fd, resources, connector, &crtc_id,
        &wanted_crtc, &primary_plane);
    if (!mode || !pipeline_found) {
        fprintf(stderr, "HDMI connector found, but profile '%s' has no compatible CRTC/primary plane/mode.\n",
            profile);
        drmModeFreeConnector(connector);
        drmModeFreeResources(resources);
        close(fd);
        return 1;
    }
    const char *type_name = drmModeGetConnectorTypeName(connector->connector_type);
    fprintf(stdout, "connector=%u type=%s-%u crtc=%u primary_plane=%u\n",
        connector->connector_id, type_name ? type_name : "unknown",
        connector->connector_type_id, crtc_id, primary_plane);
    fprintf(stdout, "profile=%s mode=%s %ux%u refresh=%.3fHz pixel_clock=%ukHz\n",
        profile, mode->name, mode->hdisplay, mode->vdisplay,
        refresh_hz(mode), mode->clock);
    if (edid_output && save_edid(fd, connector, edid_output) == 0)
        fprintf(stdout, "edid=%s\n", edid_output);
    fflush(stdout);

    drmModeCrtc *old_crtc = drmModeGetCrtc(fd, crtc_id);
    struct framebuffer fb = {0};
    int result = 1;
    if (create_framebuffer(fd, mode->hdisplay, mode->vdisplay, &fb) != 0) {
        fprintf(stderr, "Cannot create XRGB8888 test framebuffer: %s\n", strerror(errno));
        goto cleanup;
    }
    draw_pattern(&fb, mode->hdisplay, mode->vdisplay, 0);
    uint32_t connector_id = connector->connector_id;
    if (drmModeSetCrtc(fd, crtc_id, fb.id, 0, 0, &connector_id, 1, mode) != 0) {
        fprintf(stderr, "Cannot set the EDID-selected HDMI mode: %s\n", strerror(errno));
        goto cleanup;
    }
    fprintf(stdout, "TX SELF-TEST ACTIVE: animated colour bars prove HDMI-TX output.\n");
    fflush(stdout);
    result = 0;
    struct timespec started;
    clock_gettime(CLOCK_MONOTONIC, &started);
    unsigned phase = 0;
    while (!stopped) {
        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        if (seconds && (unsigned)(now.tv_sec - started.tv_sec) >= seconds)
            break;
        if (!connector_still_present(fd, connector_id)) {
            fprintf(stderr, "HDMI-TX display disconnected.\n");
            result = 75;
            break;
        }
        draw_pattern(&fb, mode->hdisplay, mode->vdisplay, ++phase);
        struct timespec pause = {.tv_sec = 0, .tv_nsec = 500000000};
        nanosleep(&pause, NULL);
    }

cleanup:
    if (old_crtc && old_crtc->mode_valid && old_crtc->buffer_id) {
        if (drmModeSetCrtc(fd, old_crtc->crtc_id, old_crtc->buffer_id,
            old_crtc->x, old_crtc->y, &connector->connector_id, 1,
            &old_crtc->mode) != 0)
            fprintf(stderr, "Warning: could not restore previous CRTC state: %s\n",
                strerror(errno));
    } else if (crtc_id) {
        drmModeSetCrtc(fd, crtc_id, 0, 0, 0, NULL, 0, NULL);
    }
    destroy_framebuffer(fd, &fb);
    if (old_crtc)
        drmModeFreeCrtc(old_crtc);
    drmModeFreeConnector(connector);
    drmModeFreeResources(resources);
    close(fd);
    return result;
}
