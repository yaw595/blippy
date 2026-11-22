// SPDX-License-Identifier: Apache-2.0
//
//  blippy-mtp.c
//  Blippy
//
//  A small command-line helper that sends one file to an Android phone over USB using MTP, the
//  "File transfer" USB mode. It needs no developer mode and no USB debugging, and it sends any file type.
//  Blippy runs it as a child process and reads its output (one line per event, see below).
//
//  Usage:
//    blippy-mtp detect
//        prints one line per phone found in a file-transfer-capable USB mode:   MTP <vid>:<pid> <name>
//    blippy-mtp send [--dest Download] <file>
//        prints:  STATUS <text> | NAME <final name on the phone> | PROGRESS <sent> <total> | DONE | ERROR <CODE> <text>
//
//  Talks to the phone with libusb (LGPL-2.1, linked statically; see THIRD_PARTY_NOTICES.md).
//  The protocol parts used are the standard PTP/MTP operations: OpenSession, GetStorageIDs, GetStorageInfo,
//  GetObjectHandles, GetObjectInfo, SendObjectInfo, SendObject, CloseSession.
//

#include <errno.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <strings.h>
#include <unistd.h>

#include "libusb.h"

// MARK: - Constants

#define CT_COMMAND  1
#define CT_DATA     2
#define CT_RESPONSE 3

#define OP_OPEN_SESSION      0x1002
#define OP_CLOSE_SESSION     0x1003
#define OP_GET_STORAGE_IDS   0x1004
#define OP_GET_STORAGE_INFO  0x1005
#define OP_GET_OBJECT_HANDLES 0x1007
#define OP_GET_OBJECT_INFO   0x1008
#define OP_SEND_OBJECT_INFO  0x100C
#define OP_SEND_OBJECT       0x100D

#define RESP_OK              0x2001
#define RESP_SESSION_OPEN    0x201E

#define FORMAT_UNDEFINED     0x3000
#define FORMAT_ASSOCIATION   0x3001

#define ROOT_PARENT          0xFFFFFFFFu
#define CHUNK                (256 * 1024)

// MARK: - State

static libusb_device_handle *H;
static int IFACE = -1;
static uint8_t EP_IN, EP_OUT;
static int MAXPKT = 512;
static uint32_t TID;
static volatile sig_atomic_t STOP;

typedef struct { uint8_t *p; size_t len, cap; } Buf;

static void buf_reserve(Buf *b, size_t extra) {
	if (b->len + extra <= b->cap) return;
	size_t cap = b->cap ? b->cap : 256;
	while (cap < b->len + extra) cap *= 2;
	b->p = realloc(b->p, cap);
	if (!b->p) { fprintf(stderr, "out of memory\n"); exit(2); }
	b->cap = cap;
}
static void buf_put(Buf *b, const void *d, size_t n) { buf_reserve(b, n); memcpy(b->p + b->len, d, n); b->len += n; }
static void put8(Buf *b, uint8_t v) { buf_put(b, &v, 1); }
static void put16(Buf *b, uint16_t v) { uint8_t t[2] = { v & 255, v >> 8 }; buf_put(b, t, 2); }
static void put32(Buf *b, uint32_t v) { uint8_t t[4] = { v & 255, (v >> 8) & 255, (v >> 16) & 255, v >> 24 }; buf_put(b, t, 4); }
static uint16_t get16(const uint8_t *p) { return (uint16_t)(p[0] | (p[1] << 8)); }
static uint32_t get32(const uint8_t *p) { return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24); }
static uint64_t get64(const uint8_t *p) { return (uint64_t)get32(p) | ((uint64_t)get32(p + 4) << 32); }

// MARK: - Output

static void say(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
#include <stdarg.h>
static void say(const char *fmt, ...) {
	va_list ap; va_start(ap, fmt); vprintf(fmt, ap); va_end(ap);
	putchar('\n'); fflush(stdout);
}
static void fail(const char *code, const char *text) {
	say("ERROR %s %s", code, text);
}

// MARK: - PTP strings (UTF-16LE with a length byte)

static void put_string(Buf *b, const char *utf8) {
	uint16_t units[256]; int n = 0;
	const unsigned char *s = (const unsigned char *)utf8;
	while (*s && n < 250) {
		uint32_t cp;
		if (*s < 0x80) { cp = *s++; }
		else if ((*s & 0xE0) == 0xC0 && s[1]) { cp = ((*s & 0x1F) << 6) | (s[1] & 0x3F); s += 2; }
		else if ((*s & 0xF0) == 0xE0 && s[1] && s[2]) { cp = ((*s & 0x0F) << 12) | ((s[1] & 0x3F) << 6) | (s[2] & 0x3F); s += 3; }
		else if ((*s & 0xF8) == 0xF0 && s[1] && s[2] && s[3]) { cp = ((*s & 0x07) << 18) | ((s[1] & 0x3F) << 12) | ((s[2] & 0x3F) << 6) | (s[3] & 0x3F); s += 4; }
		else { cp = '_'; s++; }
		if (cp >= 0x10000) { cp -= 0x10000; units[n++] = 0xD800 + (cp >> 10); units[n++] = 0xDC00 + (cp & 0x3FF); }
		else units[n++] = (uint16_t)cp;
	}
	if (n == 0) { put8(b, 0); return; }
	put8(b, (uint8_t)(n + 1));
	for (int i = 0; i < n; i++) put16(b, units[i]);
	put16(b, 0);
}

/// Reads a PTP string at p (limit end); writes UTF-8 into out. Returns bytes consumed, or 0 on error.
static size_t read_string(const uint8_t *p, const uint8_t *end, char *out, size_t outcap) {
	if (p >= end) return 0;
	int n = p[0];
	if (p + 1 + n * 2 > end) return 0;
	size_t o = 0;
	for (int i = 0; i < n; i++) {
		uint32_t u = get16(p + 1 + i * 2);
		if (u == 0) break;
		if (u >= 0xD800 && u < 0xDC00 && i + 1 < n) { uint32_t l = get16(p + 1 + (i + 1) * 2); u = 0x10000 + ((u - 0xD800) << 10) + (l - 0xDC00); i++; }
		if (o + 5 >= outcap) break;
		if (u < 0x80) out[o++] = (char)u;
		else if (u < 0x800) { out[o++] = 0xC0 | (u >> 6); out[o++] = 0x80 | (u & 0x3F); }
		else if (u < 0x10000) { out[o++] = 0xE0 | (u >> 12); out[o++] = 0x80 | ((u >> 6) & 0x3F); out[o++] = 0x80 | (u & 0x3F); }
		else { out[o++] = 0xF0 | (u >> 18); out[o++] = 0x80 | ((u >> 12) & 0x3F); out[o++] = 0x80 | ((u >> 6) & 0x3F); out[o++] = 0x80 | (u & 0x3F); }
	}
	out[o] = 0;
	return 1 + (size_t)n * 2;
}

// MARK: - USB transfers

/// Sends all bytes. Gives up after ~90 s without any progress.
static int bulk_out(const uint8_t *d, size_t n) {
	size_t sent = 0; int stalls = 0;
	while (sent < n) {
		if (STOP) return LIBUSB_ERROR_INTERRUPTED;
		int got = 0;
		int r = libusb_bulk_transfer(H, EP_OUT, (uint8_t *)d + sent, (int)(n - sent), &got, 15000);
		sent += (size_t)got;
		if (r == LIBUSB_SUCCESS) { stalls = 0; continue; }
		if (r == LIBUSB_ERROR_TIMEOUT) { if (got == 0 && ++stalls >= 6) return r; if (got > 0) stalls = 0; continue; }
		if (r == LIBUSB_ERROR_PIPE) { libusb_clear_halt(H, EP_OUT); return r; }
		return r;
	}
	return LIBUSB_SUCCESS;
}

/// Reads one whole container (header and payload) into b. Returns 0, or a libusb error.
static int read_container(Buf *b) {
	b->len = 0;
	uint32_t want = 0; int tries = 0;
	for (;;) {
		if (STOP) return LIBUSB_ERROR_INTERRUPTED;
		buf_reserve(b, 64 * 1024);
		int got = 0;
		int r = libusb_bulk_transfer(H, EP_IN, b->p + b->len, 64 * 1024, &got, 15000);
		if (r == LIBUSB_ERROR_TIMEOUT && got == 0) { if (++tries >= 6) return r; continue; }
		if (r != LIBUSB_SUCCESS && r != LIBUSB_ERROR_TIMEOUT) { if (r == LIBUSB_ERROR_PIPE) libusb_clear_halt(H, EP_IN); return r; }
		tries = 0;
		b->len += (size_t)got;
		if (b->len < 12) { if (got == 0 && b->len == 0) continue; if (got == 0) continue; continue; }
		want = get32(b->p);
		if (want == 0xFFFFFFFFu || b->len >= want) break;
	}
	return LIBUSB_SUCCESS;
}

typedef struct {
	uint16_t response;
	uint32_t params[5]; int nparams;
	Buf data;           // payload of the data phase, if the phone sent one
} Reply;

static int send_container(uint16_t type, uint16_t code, const uint32_t *params, int nparams, const uint8_t *payload, size_t plen) {
	Buf b = {0};
	put32(&b, (uint32_t)(12 + nparams * 4 + plen)); put16(&b, type); put16(&b, code); put32(&b, TID);
	for (int i = 0; i < nparams; i++) put32(&b, params[i]);
	if (plen) buf_put(&b, payload, plen);
	int r = bulk_out(b.p, b.len);
	size_t total = b.len; free(b.p);
	if (r == LIBUSB_SUCCESS && total % (size_t)MAXPKT == 0) { int g = 0; libusb_bulk_transfer(H, EP_OUT, (uint8_t *)"", 0, &g, 5000); }
	return r;
}

/// One MTP operation. `payload` is the data phase we send (for SendObjectInfo). Fills `rep`.
static int transaction(uint16_t op, const uint32_t *params, int nparams, const uint8_t *payload, size_t plen, Reply *rep) {
	memset(rep, 0, sizeof *rep);
	TID++;
	int r = send_container(CT_COMMAND, op, params, nparams, NULL, 0);
	if (r) return r;
	if (payload) { r = send_container(CT_DATA, op, NULL, 0, payload, plen); if (r) return r; }
	Buf c = {0};
	for (;;) {
		r = read_container(&c);
		if (r) { free(c.p); return r; }
		uint16_t type = get16(c.p + 4);
		if (type == CT_DATA) { buf_reserve(&rep->data, c.len); buf_put(&rep->data, c.p + 12, c.len - 12); continue; }
		if (type == CT_RESPONSE) {
			rep->response = get16(c.p + 6);
			rep->nparams = (int)((c.len - 12) / 4); if (rep->nparams > 5) rep->nparams = 5;
			for (int i = 0; i < rep->nparams; i++) rep->params[i] = get32(c.p + 12 + i * 4);
			break;
		}
		// events and anything else: ignore
	}
	free(c.p);
	return LIBUSB_SUCCESS;
}

// MARK: - Finding and opening the phone

static int find_mtp_interface(libusb_device *dev, int *iface, uint8_t *in, uint8_t *out, int *maxpkt) {
	struct libusb_config_descriptor *cfg;
	if (libusb_get_active_config_descriptor(dev, &cfg) != 0) return 0;
	int found = 0;
	for (int i = 0; i < cfg->bNumInterfaces && !found; i++) {
		const struct libusb_interface_descriptor *a = &cfg->interface[i].altsetting[0];
		int imaging = a->bInterfaceClass == 6 && a->bInterfaceSubClass == 1 && a->bInterfaceProtocol == 1;
		int vendor = a->bInterfaceClass == 0xFF && a->bNumEndpoints >= 3;
		if (!imaging && !vendor) continue;
		int hasIn = 0, hasOut = 0; uint8_t ein = 0, eout = 0; int mp = 512;
		for (int e = 0; e < a->bNumEndpoints; e++) {
			const struct libusb_endpoint_descriptor *ep = &a->endpoint[e];
			if ((ep->bmAttributes & 3) != LIBUSB_TRANSFER_TYPE_BULK) continue;
			if (ep->bEndpointAddress & 0x80) { ein = ep->bEndpointAddress; hasIn = 1; } else { eout = ep->bEndpointAddress; hasOut = 1; mp = ep->wMaxPacketSize; }
		}
		if (!(hasIn && hasOut)) continue;
		if (vendor) {
			// Only accept a vendor-class interface that calls itself MTP.
			libusb_device_handle *tmp = NULL; char name[64] = "";
			if (libusb_open(dev, &tmp) == 0) {
				if (a->iInterface) libusb_get_string_descriptor_ascii(tmp, a->iInterface, (unsigned char *)name, sizeof name);
				libusb_close(tmp);
			}
			if (strncmp(name, "MTP", 3) != 0) continue;
		}
		*iface = a->bInterfaceNumber; *in = ein; *out = eout; *maxpkt = mp > 0 ? mp : 512;
		found = 1;
	}
	libusb_free_config_descriptor(cfg);
	return found;
}

static void product_name(libusb_device *dev, char *out, size_t cap) {
	snprintf(out, cap, "Phone");
	struct libusb_device_descriptor d;
	if (libusb_get_device_descriptor(dev, &d) != 0 || !d.iProduct) return;
	libusb_device_handle *tmp = NULL;
	if (libusb_open(dev, &tmp) == 0) {
		unsigned char s[128] = "";
		if (libusb_get_string_descriptor_ascii(tmp, d.iProduct, s, sizeof s) > 0 && s[0]) snprintf(out, cap, "%s", s);
		libusb_close(tmp);
	}
}

static int cmd_detect(void) {
	libusb_context *ctx; if (libusb_init(&ctx) != 0) return 1;
	libusb_device **list; ssize_t n = libusb_get_device_list(ctx, &list);
	for (ssize_t i = 0; i < n; i++) {
		int iface; uint8_t in, out; int mp;
		if (!find_mtp_interface(list[i], &iface, &in, &out, &mp)) continue;
		struct libusb_device_descriptor d; libusb_get_device_descriptor(list[i], &d);
		char name[128]; product_name(list[i], name, sizeof name);
		printf("MTP %04x:%04x %s\n", d.idVendor, d.idProduct, name);
	}
	libusb_free_device_list(list, 1);
	libusb_exit(ctx);
	return 0;
}

static void release_camera_daemon(void) {
	// macOS's own camera service grabs phones in file-transfer mode. It restarts by itself when needed.
	system("/usr/bin/killall -9 ptpcamera >/dev/null 2>&1");
}

static int open_phone(libusb_context *ctx) {
	libusb_device **list; ssize_t n = libusb_get_device_list(ctx, &list);
	libusb_device *target = NULL;
	for (ssize_t i = 0; i < n && !target; i++) {
		int iface; uint8_t in, out; int mp;
		if (find_mtp_interface(list[i], &iface, &in, &out, &mp)) { target = list[i]; IFACE = iface; EP_IN = in; EP_OUT = out; MAXPKT = mp; }
	}
	if (!target) { libusb_free_device_list(list, 1); return 1; }
	int r = -1;
	for (int attempt = 0; attempt < 8; attempt++) {
		release_camera_daemon();
		r = libusb_open(target, &H);
		if (r == 0) {
			r = libusb_claim_interface(H, IFACE);
			if (r == 0) break;
			libusb_close(H); H = NULL;
		}
		usleep(400 * 1000);
	}
	libusb_free_device_list(list, 1);
	return r == 0 ? 0 : 2;
}

// MARK: - MTP helpers

typedef struct { uint32_t handle; uint16_t format; char name[256]; uint32_t size; } Entry;

static int object_info(uint32_t handle, Entry *e) {
	Reply rep; uint32_t p[1] = { handle };
	if (transaction(OP_GET_OBJECT_INFO, p, 1, NULL, 0, &rep) != 0 || rep.response != RESP_OK || rep.data.len < 53) { free(rep.data.p); return 0; }
	e->handle = handle; e->format = get16(rep.data.p + 4); e->size = get32(rep.data.p + 8);
	e->name[0] = 0; read_string(rep.data.p + 52, rep.data.p + rep.data.len, e->name, sizeof e->name);
	free(rep.data.p);
	return 1;
}

/// Handles of everything directly inside `parent` (ROOT_PARENT for the top level).
static uint32_t *children(uint32_t storage, uint32_t parent, uint32_t *count) {
	Reply rep; uint32_t p[3] = { storage, 0, parent };
	*count = 0;
	if (transaction(OP_GET_OBJECT_HANDLES, p, 3, NULL, 0, &rep) != 0 || rep.response != RESP_OK || rep.data.len < 4) { free(rep.data.p); return NULL; }
	uint32_t n = get32(rep.data.p);
	if (rep.data.len < 4 + (size_t)n * 4) n = (uint32_t)((rep.data.len - 4) / 4);
	uint32_t *out = malloc((n ? n : 1) * 4);
	for (uint32_t i = 0; i < n; i++) out[i] = get32(rep.data.p + 4 + i * 4);
	free(rep.data.p);
	*count = n;
	return out;
}

static void build_object_info(Buf *b, uint32_t storage, uint16_t format, uint64_t size, uint32_t parent, const char *name) {
	put32(b, storage); put16(b, format); put16(b, 0);
	put32(b, size > 0xFFFFFFFFull ? 0xFFFFFFFFu : (uint32_t)size);
	put16(b, 0); put32(b, 0); put32(b, 0); put32(b, 0); put32(b, 0); put32(b, 0); put32(b, 0);
	put32(b, parent == ROOT_PARENT ? 0 : parent);
	put16(b, format == FORMAT_ASSOCIATION ? 1 : 0); put32(b, 0); put32(b, 0);
	put_string(b, name); put8(b, 0); put8(b, 0); put8(b, 0);
}

static const char *describe(uint16_t code) {
	switch (code) {
		case 0x2002: return "general error";
		case 0x2005: return "operation not supported";
		case 0x2008: return "invalid storage";
		case 0x2009: return "invalid object";
		case 0x200C: return "storage full";
		case 0x200D: return "write protected";
		case 0x2010: return "no valid object info";
		case 0x2019: return "device busy";
		case 0x201C: return "invalid parent";
		default: return "refused by the phone";
	}
}

static void on_signal(int sig) { (void)sig; STOP = 1; }

// MARK: - send

static int cmd_send(const char *dest, const char *path) {
	struct stat st;
	if (stat(path, &st) != 0 || !S_ISREG(st.st_mode)) { fail("FILE", "Can't read that file"); return 1; }
	uint64_t size = (uint64_t)st.st_size;
	FILE *f = fopen(path, "rb");
	if (!f) { fail("FILE", "Can't read that file"); return 1; }

	libusb_context *ctx;
	if (libusb_init(&ctx) != 0) { fail("USB", "USB isn't available"); return 1; }
	say("STATUS connecting");
	int o = open_phone(ctx);
	if (o == 1) { fail("NO_DEVICE", "No phone in File transfer mode"); return 1; }
	if (o == 2) { fail("ACCESS", "Couldn't open the phone. Close other apps that use it, then unplug and replug"); return 1; }

	int code = 1;
	Reply rep; uint32_t p[3];
	p[0] = 1; TID = 0;
	if (transaction(OP_OPEN_SESSION, p, 1, NULL, 0, &rep) != 0) { fail("IO", "The phone didn't answer"); goto done; }
	free(rep.data.p);
	if (rep.response != RESP_OK && rep.response != RESP_SESSION_OPEN) { fail("REFUSED", describe(rep.response)); goto done; }
	say("STATUS session");

	// Storage: the first one that can be written to.
	if (transaction(OP_GET_STORAGE_IDS, NULL, 0, NULL, 0, &rep) != 0) { fail("IO", "The phone didn't answer"); goto done; }
	uint32_t storage = 0;
	if (rep.data.len >= 4) {
		uint32_t n = get32(rep.data.p);
		for (uint32_t i = 0; i < n && 4 + (i + 1) * 4 <= rep.data.len; i++) {
			uint32_t id = get32(rep.data.p + 4 + i * 4);
			Reply si; uint32_t sp[1] = { id };
			if (transaction(OP_GET_STORAGE_INFO, sp, 1, NULL, 0, &si) == 0 && si.response == RESP_OK && si.data.len >= 22) {
				uint16_t access = get16(si.data.p + 4);
				uint64_t freeBytes = get64(si.data.p + 14);
				if (access == 0 || access == 0xFFFF) {
					if (freeBytes != 0xFFFFFFFFFFFFFFFFull && freeBytes < size) { free(si.data.p); free(rep.data.p); fail("FULL", "Not enough space on the phone"); goto done; }
					storage = id; free(si.data.p); break;
				}
			}
			free(si.data.p);
		}
	}
	free(rep.data.p);
	if (!storage) { fail("LOCKED", "Unlock the phone and keep the screen on"); goto done; }
	say("STATUS storage");

	// Folder: Download at the top level (made if missing).
	uint32_t parent = ROOT_PARENT;
	if (dest && *dest) {
		uint32_t n; uint32_t *top = children(storage, ROOT_PARENT, &n);
		int found = 0;
		for (uint32_t i = 0; i < n && !found; i++) {
			Entry e;
			if (object_info(top[i], &e) && e.format == FORMAT_ASSOCIATION && strcasecmp(e.name, dest) == 0) { parent = e.handle; found = 1; }
		}
		free(top);
		if (!found) {
			Buf info = {0}; build_object_info(&info, storage, FORMAT_ASSOCIATION, 0, ROOT_PARENT, dest);
			uint32_t sp[2] = { storage, 0 };
			Reply cr;
			if (transaction(OP_SEND_OBJECT_INFO, sp, 2, info.p, info.len, &cr) == 0 && cr.response == RESP_OK && cr.nparams >= 3) parent = cr.params[2];
			free(info.p); free(cr.data.p);
		}
	}

	// A name that doesn't exist yet in that folder.
	char base[256], ext[64] = "", name[300];
	const char *slash = strrchr(path, '/'); const char *fname = slash ? slash + 1 : path;
	snprintf(base, sizeof base, "%s", fname);
	char *dot = strrchr(base, '.');
	if (dot && dot != base && strlen(dot) < sizeof ext) { snprintf(ext, sizeof ext, "%s", dot); *dot = 0; }
	snprintf(name, sizeof name, "%s%s", base, ext);
	{
		uint32_t n; uint32_t *kids = children(storage, parent, &n);
		char (*taken)[256] = n ? malloc((size_t)n * 256) : NULL; uint32_t have = 0;
		for (uint32_t i = 0; i < n && i < 20000; i++) { Entry e; if (object_info(kids[i], &e)) { snprintf(taken[have++], 256, "%s", e.name); } }
		for (int counter = 1; counter < 1000; counter++) {
			int clash = 0;
			for (uint32_t i = 0; i < have; i++) if (strcasecmp(taken[i], name) == 0) { clash = 1; break; }
			if (!clash) break;
			snprintf(name, sizeof name, "%s (%d)%s", base, counter, ext);
		}
		free(taken); free(kids);
	}
	say("NAME %s", name);

	// Announce the file, then send its bytes.
	Buf info = {0}; build_object_info(&info, storage, FORMAT_UNDEFINED, size, parent, name);
	uint32_t sp[2] = { storage, parent == ROOT_PARENT ? 0 : parent };
	Reply ir;
	int r = transaction(OP_SEND_OBJECT_INFO, sp, 2, info.p, info.len, &ir);
	free(info.p); free(ir.data.p);
	if (r != 0) { fail("IO", "The phone didn't answer"); goto done; }
	if (ir.response != RESP_OK || ir.nparams < 3) {
		if (ir.response == 0x200C) fail("FULL", "Not enough space on the phone");
		else fail("REFUSED", describe(ir.response));
		goto done;
	}
	uint32_t handle = ir.params[2];

	TID++;
	if (send_container(CT_COMMAND, OP_SEND_OBJECT, NULL, 0, NULL, 0) != 0) { fail("IO", "The phone didn't answer"); goto done; }

	uint8_t *chunk = malloc(CHUNK + 12);
	uint64_t sent = 0, announced = size + 12;
	uint32_t length = announced > 0xFFFFFFFFull ? 0xFFFFFFFFu : (uint32_t)announced;
	chunk[0] = length & 255; chunk[1] = (length >> 8) & 255; chunk[2] = (length >> 16) & 255; chunk[3] = length >> 24;
	chunk[4] = CT_DATA; chunk[5] = 0; chunk[6] = OP_SEND_OBJECT & 255; chunk[7] = OP_SEND_OBJECT >> 8;
	chunk[8] = TID & 255; chunk[9] = (TID >> 8) & 255; chunk[10] = (TID >> 16) & 255; chunk[11] = TID >> 24;
	size_t first = fread(chunk + 12, 1, CHUNK - 12, f);
	size_t toSend = 12 + first;
	struct timeval last = {0}; gettimeofday(&last, NULL);
	say("PROGRESS 0 %llu", (unsigned long long)size);
	for (;;) {
		r = bulk_out(chunk, toSend);
		if (r != 0) break;
		sent += (toSend - (sent == 0 ? 12 : 0));
		struct timeval now; gettimeofday(&now, NULL);
		if ((now.tv_sec - last.tv_sec) * 1000 + (now.tv_usec - last.tv_usec) / 1000 >= 250) { say("PROGRESS %llu %llu", (unsigned long long)sent, (unsigned long long)size); last = now; }
		if (sent >= size) break;
		size_t got = fread(chunk, 1, CHUNK, f);
		if (got == 0) { r = LIBUSB_ERROR_IO; break; }
		toSend = got;
	}
	free(chunk);
	if (r == LIBUSB_ERROR_INTERRUPTED) {
		uint8_t cancel[6] = { 0x01, 0x40, (uint8_t)TID, (uint8_t)(TID >> 8), (uint8_t)(TID >> 16), (uint8_t)(TID >> 24) };
		libusb_control_transfer(H, 0x21, 0x64, 0, (uint16_t)IFACE, cancel, sizeof cancel, 2000);
		fail("CANCELED", "Canceled"); code = 130; goto done;
	}
	if (r != 0) { fail("IO", "The cable or phone stopped answering"); goto done; }
	if ((announced) % (uint64_t)MAXPKT == 0) { int g = 0; libusb_bulk_transfer(H, EP_OUT, (uint8_t *)"", 0, &g, 5000); }

	// The phone's answer to SendObject.
	Buf c = {0};
	r = read_container(&c);
	if (r != 0) { free(c.p); fail("IO", "The phone didn't confirm the file"); goto done; }
	uint16_t resp = get16(c.p + 6); free(c.p);
	if (resp != RESP_OK) { if (resp == 0x200C) fail("FULL", "Not enough space on the phone"); else fail("REFUSED", describe(resp)); goto done; }

	// Check the copy: the phone must report the same size.
	if (size < 0xFFFFFFFFull) {
		Entry check;
		if (object_info(handle, &check) && check.size != (uint32_t)size) { fail("SIZE", "The copy on the phone is incomplete"); goto done; }
	}
	say("PROGRESS %llu %llu", (unsigned long long)size, (unsigned long long)size);
	say("DONE");
	code = 0;

done:
	{
		Reply cl; uint32_t cp[1] = { 1 };
		if (H) { transaction(OP_CLOSE_SESSION, cp, 0, NULL, 0, &cl); free(cl.data.p); (void)cp; }
	}
	if (H) { libusb_release_interface(H, IFACE); libusb_close(H); }
	libusb_exit(ctx);
	fclose(f);
	return code;
}

int main(int argc, char **argv) {
	setvbuf(stdout, NULL, _IOLBF, 0);
	signal(SIGTERM, on_signal); signal(SIGINT, on_signal); signal(SIGPIPE, SIG_IGN);
	if (argc >= 2 && strcmp(argv[1], "detect") == 0) return cmd_detect();
	if (argc >= 3 && strcmp(argv[1], "send") == 0) {
		const char *dest = "Download"; const char *path = NULL;
		for (int i = 2; i < argc; i++) {
			if (strcmp(argv[i], "--dest") == 0 && i + 1 < argc) dest = argv[++i];
			else path = argv[i];
		}
		if (!path) { fprintf(stderr, "usage: blippy-mtp send [--dest Download] <file>\n"); return 2; }
		return cmd_send(dest, path);
	}
	fprintf(stderr, "usage: blippy-mtp detect | send [--dest Download] <file>\n");
	return 2;
}
