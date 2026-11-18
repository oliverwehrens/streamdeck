#ifndef DECK_LINUX_H
#define DECK_LINUX_H

// Wrappers for the hidraw and uinput ioctls. Their request codes are function-like macros
// (HIDIOCSFEATURE(len), UI_SET_KEYBIT, ...), which Swift cannot import.
//
// The Static Linux SDK's musl sysroot ships no kernel (uapi) headers, so the few codes this
// project needs are defined here from the stable kernel ABI (linux/input-event-codes.h,
// linux/uinput.h, linux/hidraw.h). Values must not change; the kernel guarantees that.

#include <stddef.h>
#include <stdint.h>

// Event types and sync codes.
#define EV_SYN 0x00
#define EV_KEY 0x01
#define SYN_REPORT 0
#define BUS_VIRTUAL 0x06

// Key codes: the main alphanumeric block, modifiers, navigation, function and media keys.
#define KEY_ESC 1
#define KEY_1 2
#define KEY_2 3
#define KEY_3 4
#define KEY_4 5
#define KEY_5 6
#define KEY_6 7
#define KEY_7 8
#define KEY_8 9
#define KEY_9 10
#define KEY_0 11
#define KEY_MINUS 12
#define KEY_EQUAL 13
#define KEY_BACKSPACE 14
#define KEY_TAB 15
#define KEY_Q 16
#define KEY_W 17
#define KEY_E 18
#define KEY_R 19
#define KEY_T 20
#define KEY_Y 21
#define KEY_U 22
#define KEY_I 23
#define KEY_O 24
#define KEY_P 25
#define KEY_LEFTBRACE 26
#define KEY_RIGHTBRACE 27
#define KEY_ENTER 28
#define KEY_LEFTCTRL 29
#define KEY_A 30
#define KEY_S 31
#define KEY_D 32
#define KEY_F 33
#define KEY_G 34
#define KEY_H 35
#define KEY_J 36
#define KEY_K 37
#define KEY_L 38
#define KEY_SEMICOLON 39
#define KEY_APOSTROPHE 40
#define KEY_GRAVE 41
#define KEY_LEFTSHIFT 42
#define KEY_BACKSLASH 43
#define KEY_Z 44
#define KEY_X 45
#define KEY_C 46
#define KEY_V 47
#define KEY_B 48
#define KEY_N 49
#define KEY_M 50
#define KEY_COMMA 51
#define KEY_DOT 52
#define KEY_SLASH 53
#define KEY_LEFTALT 56
#define KEY_SPACE 57
#define KEY_F1 59
#define KEY_F2 60
#define KEY_F3 61
#define KEY_F4 62
#define KEY_F5 63
#define KEY_F6 64
#define KEY_F7 65
#define KEY_F8 66
#define KEY_F9 67
#define KEY_F10 68
#define KEY_102ND 86
#define KEY_F11 87
#define KEY_F12 88
#define KEY_RO 89
#define KEY_HOME 102
#define KEY_UP 103
#define KEY_PAGEUP 104
#define KEY_LEFT 105
#define KEY_RIGHT 106
#define KEY_END 107
#define KEY_DOWN 108
#define KEY_PAGEDOWN 109
#define KEY_DELETE 111
#define KEY_MUTE 113
#define KEY_VOLUMEDOWN 114
#define KEY_VOLUMEUP 115
#define KEY_YEN 124
#define KEY_LEFTMETA 125
#define KEY_NEXTSONG 163
#define KEY_PLAYPAUSE 164
#define KEY_PREVIOUSSONG 165
#define KEY_F13 183
#define KEY_F14 184
#define KEY_F15 185
#define KEY_F16 186
#define KEY_F17 187
#define KEY_F18 188
#define KEY_F19 189
#define KEY_F20 190
#define KEY_BRIGHTNESSDOWN 224
#define KEY_BRIGHTNESSUP 225

// hidraw feature reports. `buffer[0]` is the report ID. Return the ioctl result (bytes or -1, errno set).
int deck_hid_set_feature(int fd, const uint8_t *buffer, size_t length);
int deck_hid_get_feature(int fd, uint8_t *buffer, size_t length);

// Creates a uinput keyboard that can send `keys`. Returns 0 or -1 with errno set.
int deck_uinput_create(int fd, const char *name, const uint16_t *keys, size_t count);
int deck_uinput_destroy(int fd);

// Writes one input event. Returns 0 or -1 with errno set.
int deck_uinput_emit(int fd, uint16_t type, uint16_t code, int32_t value);

#endif
