#include "deck_linux.h"

#include <errno.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

// Kernel ABI structs and request codes (linux/input.h, linux/uinput.h, linux/hidraw.h); see the header.

struct deck_input_id {
    uint16_t bustype;
    uint16_t vendor;
    uint16_t product;
    uint16_t version;
};

#define DECK_UINPUT_MAX_NAME_SIZE 80

struct deck_uinput_setup {
    struct deck_input_id id;
    char name[DECK_UINPUT_MAX_NAME_SIZE];
    uint32_t ff_effects_max;
};

// `struct input_event` on 64-bit Linux: a `struct timeval` (two longs), then type, code, value.
struct deck_input_event {
    long tv_sec;
    long tv_usec;
    uint16_t type;
    uint16_t code;
    int32_t value;
};

_Static_assert(sizeof(struct deck_uinput_setup) == 92, "struct uinput_setup layout");
_Static_assert(sizeof(long) == 8, "only 64-bit Linux is supported");
_Static_assert(sizeof(struct deck_input_event) == 24, "struct input_event layout on 64-bit");

#define DECK_UINPUT_IOCTL_BASE 'U'
#define DECK_UI_DEV_CREATE _IO(DECK_UINPUT_IOCTL_BASE, 1)
#define DECK_UI_DEV_DESTROY _IO(DECK_UINPUT_IOCTL_BASE, 2)
#define DECK_UI_DEV_SETUP _IOW(DECK_UINPUT_IOCTL_BASE, 3, struct deck_uinput_setup)
#define DECK_UI_SET_EVBIT _IOW(DECK_UINPUT_IOCTL_BASE, 100, int)
#define DECK_UI_SET_KEYBIT _IOW(DECK_UINPUT_IOCTL_BASE, 101, int)

#define DECK_HIDIOCSFEATURE(len) _IOC(_IOC_WRITE | _IOC_READ, 'H', 0x06, len)
#define DECK_HIDIOCGFEATURE(len) _IOC(_IOC_WRITE | _IOC_READ, 'H', 0x07, len)

int deck_hid_set_feature(int fd, const uint8_t *buffer, size_t length) {
    return ioctl(fd, DECK_HIDIOCSFEATURE(length), buffer);
}

int deck_hid_get_feature(int fd, uint8_t *buffer, size_t length) {
    return ioctl(fd, DECK_HIDIOCGFEATURE(length), buffer);
}

int deck_uinput_create(int fd, const char *name, const uint16_t *keys, size_t count) {
    if (ioctl(fd, DECK_UI_SET_EVBIT, EV_KEY) < 0) return -1;
    if (ioctl(fd, DECK_UI_SET_EVBIT, EV_SYN) < 0) return -1;
    for (size_t i = 0; i < count; i++) {
        if (ioctl(fd, DECK_UI_SET_KEYBIT, (int)keys[i]) < 0) return -1;
    }
    struct deck_uinput_setup setup;
    memset(&setup, 0, sizeof setup);
    setup.id.bustype = BUS_VIRTUAL;
    setup.id.vendor = 0x0fd9;
    setup.id.product = 0x7fff;
    strncpy(setup.name, name, DECK_UINPUT_MAX_NAME_SIZE - 1);
    if (ioctl(fd, DECK_UI_DEV_SETUP, &setup) < 0) return -1;
    return ioctl(fd, DECK_UI_DEV_CREATE) < 0 ? -1 : 0;
}

int deck_uinput_destroy(int fd) {
    return ioctl(fd, DECK_UI_DEV_DESTROY) < 0 ? -1 : 0;
}

int deck_uinput_emit(int fd, uint16_t type, uint16_t code, int32_t value) {
    struct deck_input_event event;
    memset(&event, 0, sizeof event);
    event.type = type;
    event.code = code;
    event.value = value;
    ssize_t written;
    do {
        written = write(fd, &event, sizeof event);
    } while (written < 0 && errno == EINTR);
    if (written != (ssize_t)sizeof event) {
        if (written >= 0) errno = EIO;
        return -1;
    }
    return 0;
}
