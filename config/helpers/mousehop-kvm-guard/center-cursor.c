/* Warp the niri compositor cursor to an absolute layout position.
 *
 * Usage: mousehop-center-cursor <target_x> <target_y> <layout_w> <layout_h>
 *
 * Coordinates are in the compositor's global layout space; layout_w/layout_h
 * describe the full bounding box (as niri reports it through its IPC).
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>
#include "virtual-pointer.h"

static struct wl_display *display;
static struct wl_seat *seat;
static struct zwlr_virtual_pointer_manager_v1 *vp_manager;

static void reg_global(void *d, struct wl_registry *reg, uint32_t name,
                       const char *iface, uint32_t version) {
    (void)d;
    if (!strcmp(iface, wl_seat_interface.name))
        seat = wl_registry_bind(reg, name, &wl_seat_interface, version < 7 ? version : 7);
    else if (!strcmp(iface, zwlr_virtual_pointer_manager_v1_interface.name))
        vp_manager = wl_registry_bind(reg, name, &zwlr_virtual_pointer_manager_v1_interface,
                                      version < 2 ? version : 2);
}
static void reg_remove(void *d, struct wl_registry *reg, uint32_t name) { (void)d; (void)reg; (void)name; }
static const struct wl_registry_listener reg_listener = { .global = reg_global, .global_remove = reg_remove };

static uint32_t now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

int main(int argc, char **argv) {
    if (argc < 5) {
        fprintf(stderr, "usage: %s <target_x> <target_y> <layout_w> <layout_h>\n", argv[0]);
        return 2;
    }
    uint32_t tx = (uint32_t)strtoul(argv[1], NULL, 10);
    uint32_t ty = (uint32_t)strtoul(argv[2], NULL, 10);
    uint32_t w = (uint32_t)strtoul(argv[3], NULL, 10);
    uint32_t h = (uint32_t)strtoul(argv[4], NULL, 10);
    if (!w || !h) { fprintf(stderr, "empty layout\n"); return 2; }

    display = wl_display_connect(NULL);
    if (!display) { fprintf(stderr, "no wayland display\n"); return 1; }
    struct wl_registry *reg = wl_display_get_registry(display);
    wl_registry_add_listener(reg, &reg_listener, NULL);
    wl_display_roundtrip(display);
    wl_display_roundtrip(display);
    if (!vp_manager) { fprintf(stderr, "no zwlr_virtual_pointer_manager_v1\n"); return 1; }

    struct zwlr_virtual_pointer_v1 *vp =
        zwlr_virtual_pointer_manager_v1_create_virtual_pointer(vp_manager, seat);
    wl_display_roundtrip(display);

    zwlr_virtual_pointer_v1_motion_absolute(vp, now_ms(), tx, ty, w, h);
    zwlr_virtual_pointer_v1_frame(vp);
    wl_display_flush(display);
    usleep(120000);

    zwlr_virtual_pointer_v1_destroy(vp);
    wl_display_roundtrip(display);
    wl_display_disconnect(display);
    fprintf(stderr, "warped cursor to (%u, %u) in %ux%u layout\n", tx, ty, w, h);
    return 0;
}
