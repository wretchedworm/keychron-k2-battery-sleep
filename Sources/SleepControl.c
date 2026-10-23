#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hid/IOHIDManager.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <pwd.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>

/* Firmware-specific protocol: fail closed on any different layout. */
static const uint8_t supported_version[] = {0xb1,0x25,0x08,0x0a,0xc0,0x03,'2','0','2','1','0','8','2','0'};
static const uint32_t supported_vtable[] = {0x2066a5,0x2545,0x2659,0x26a5,0x26c7,0x272b,0x2779};
static const uint8_t toggle_code[32] = {0x10,0xb5,0xd0,0xf8,0x74,0x1,0xe,0xf6,0x9f,0xfe,0x1c,0x4c,0x60,0x7c,0x55,0x28,0xf,0xd0,0x55,0x20,0x60,0x74,0x19,0x48,0x1,0x22,0xbf,0x21,0x11,0x30,0xf,0xf6};
static const uint8_t dispatcher_code[32] = {0x7c,0xb5,0x15,0x46,0x1c,0x46,0xdd,0xe9,0x6,0x23,0x3,0x2d,0xe,0xd1,0x6,0x79,0xa6,0x42,0xd,0xd0,0x46,0x79,0xa6,0x42,0xa,0xd0,0xc6,0x79,0xa6,0x42,0x7,0xd0};
static volatile sig_atomic_t mutation_started;
static uint8_t answer[64];
static CFIndex answer_length;
static IOHIDDeviceRef waiting_device;
static const char *read_error = "readFailure";

static uint32_t le32(const uint8_t *p) {
    return (uint32_t)p[0] | (uint32_t)p[1]<<8 | (uint32_t)p[2]<<16 | (uint32_t)p[3]<<24;
}
static bool valid_sleep(uint8_t value) { return value == 0x55 || value == 0xaa; }
static bool valid_version(const uint8_t *bytes, size_t length) {
    return length >= sizeof(supported_version) && !memcmp(bytes, supported_version, sizeof(supported_version));
}
static bool valid_memory_response(const uint8_t *bytes, size_t size, uint32_t address, unsigned length) {
    if (length == 0 || length > 32 || size != length + 8 || bytes[0] != 0x72 ||
        le32(bytes + 1) != address || bytes[5] != length || bytes[6] != 0) return false;
    unsigned sum = 0;
    for (size_t i = 0; i < size; i++) sum += bytes[i];
    return (sum & 255) == 0;
}
static bool valid_neighbors(const uint8_t before[32], const uint8_t after[32], uint8_t desired) {
    for (unsigned i = 0; i < 32; i++) if (after[i] != (i == 15 ? desired : before[i])) return false;
    return true;
}
static void finish(const char *status, uint8_t sleep) {
    if (!strcmp(status, "fresh") && valid_sleep(sleep))
        printf("{\"version\":1,\"status\":\"fresh\",\"sleep\":\"%s\"}\n", sleep == 0x55 ? "on" : "off");
    else printf("{\"version\":1,\"status\":\"%s\"}\n", status);
}
static void timeout_handler(int signal_number) {
    (void)signal_number;
    const char *message = mutation_started ? "{\"version\":1,\"status\":\"verificationFailed\"}\n" : "{\"version\":1,\"status\":\"readFailure\"}\n";
    /* Only async-signal-safe operations: even an unresponsive HID call is bounded. */
    size_t count = mutation_started ? sizeof("{\"version\":1,\"status\":\"verificationFailed\"}\n") - 1 : sizeof("{\"version\":1,\"status\":\"readFailure\"}\n") - 1;
    (void)write(STDOUT_FILENO, message, count);
    _exit(0);
}
static void report(void *context, IOReturn result, void *sender, IOHIDReportType type,
                   uint32_t id, uint8_t *bytes, CFIndex length) {
    (void)context;
    /* Never retain or inspect normal key reports. */
    if (result || sender != waiting_device || type != kIOHIDReportTypeInput || id != 0xb1 ||
        length < 2 || length > (CFIndex)sizeof(answer)) return;
    if (bytes[0] != 0xb1 || bytes[1] != 0x25) return;
    memcpy(answer, bytes, (size_t)length); answer_length = length;
}
static bool io_success(IOReturn result) {
    if (!result) return true;
    read_error = result == kIOReturnNotPermitted ? "accessDenied" : "readFailure";
    fprintf(stderr, "HID request failed: %08x\n", (unsigned)result);
    return false;
}
static bool version_query(IOHIDDeviceRef device) {
    uint8_t request[42] = {0xb2,0x25};
    waiting_device = device; answer_length = 0;
    if (!io_success(IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0xb2, request, sizeof(request)))) return false;
    double end = CFAbsoluteTimeGetCurrent() + 2;
    while (!answer_length && CFAbsoluteTimeGetCurrent() < end)
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.025, false);
    waiting_device = NULL;
    if (!answer_length) return false;
    if (!valid_version(answer, (size_t)answer_length)) { read_error = "unsupported"; return false; }
    return true;
}
static bool memory_read(IOHIDDeviceRef device, uint32_t address, unsigned length, uint8_t *out) {
    if (!length || length > 32) return false;
    uint8_t request[8] = {0x71,address,address>>8,address>>16,address>>24,length,0,0};
    for (unsigned i = 0; i < 7; i++) request[7] -= request[i];
    if (!io_success(IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0x71, request, sizeof(request)))) return false;
    uint8_t response[40] = {0x72}; CFIndex size = length + 8;
    if (!io_success(IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0x72, response, &size))) return false;
    if (!valid_memory_response(response, (size_t)size, address, length)) return false;
    memcpy(out, response + 7, length); return true;
}
static bool feature(IOHIDDeviceRef device, uint8_t *bytes, unsigned length) {
    return io_success(IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, bytes[0], bytes, length));
}
static bool numeric_property(IOHIDDeviceRef device, CFStringRef key, int expected) {
    CFTypeRef value = IOHIDDeviceGetProperty(device, key); int number = 0;
    return value && CFGetTypeID(value) == CFNumberGetTypeID() &&
        CFNumberGetValue(value, kCFNumberIntType, &number) && number == expected;
}
typedef struct { IOHIDManagerRef manager; CFSetRef devices; IOHIDDeviceRef device; } Connection;
static void disconnect_device(Connection *connection) {
    waiting_device = NULL;
    if (connection->manager) {
        IOHIDManagerUnscheduleFromRunLoop(connection->manager, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        IOHIDManagerClose(connection->manager, kIOHIDOptionsTypeNone);
    }
    if (connection->devices) CFRelease(connection->devices);
    if (connection->manager) CFRelease(connection->manager);
    memset(connection, 0, sizeof(*connection));
}
static const char *connect_device(Connection *connection) {
    connection->manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (!connection->manager) return "readFailure";
    const void *keys[] = {CFSTR(kIOHIDProductKey), CFSTR(kIOHIDTransportKey)};
    const void *values[] = {CFSTR("Keychron K2"), CFSTR("Bluetooth")};
    CFDictionaryRef match = CFDictionaryCreate(NULL, keys, values, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    IOHIDManagerSetDeviceMatching(connection->manager, match); CFRelease(match);
    IOHIDManagerRegisterInputReportCallback(connection->manager, report, NULL);
    IOHIDManagerScheduleWithRunLoop(connection->manager, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    IOReturn result = IOHIDManagerOpen(connection->manager, kIOHIDOptionsTypeNone);
    if (result) return result == kIOReturnNotPermitted ? "accessDenied" : "readFailure";
    connection->devices = IOHIDManagerCopyDevices(connection->manager);
    CFIndex count = connection->devices ? CFSetGetCount(connection->devices) : 0;
    if (!count) return "disconnected";
    if (count != 1) return "ambiguous";
    CFSetGetValues(connection->devices, (const void **)&connection->device);
    if (!numeric_property(connection->device, CFSTR(kIOHIDVendorIDKey), 0x05ac) ||
        !numeric_property(connection->device, CFSTR(kIOHIDProductIDKey), 0x024f)) return "unsupported";
    return NULL;
}
static bool write_guards(IOHIDDeviceRef device, uint8_t *live, uint8_t before[32]) {
    uint8_t code[32];
    read_error = "readFailure";
    if (!memory_read(device,0x207b88,32,code)) return false;
    if (memcmp(code,toggle_code,32)) { read_error = "unsupported"; return false; }
    if (!memory_read(device,0x2066a4,32,code)) return false;
    if (memcmp(code,dispatcher_code,32)) { read_error = "unsupported"; return false; }
    uint8_t config[4], vs[9], selector[1], callbacks[24], singleton[4], object[32], vtable[28];
    read_error = "readFailure";
    if (!memory_read(device,0x205e10,4,config) || !memory_read(device,0x200a02,9,vs) ||
        !memory_read(device,0x20101c,1,selector) || !memory_read(device,0x201858,24,callbacks) ||
        !memory_read(device,0x2005c0,4,singleton)) return false;
    read_error = "unsupported";
    if (((config[0] & 0x7f) >> 4) != 1 || le32(vs+1) != 0x7e00 || le32(vs+5) != 0x1ff || selector[0] != 0xa0) return false;
    for (unsigned i = 0; i < sizeof(callbacks); i++) if (callbacks[i]) return false;
    uint32_t pointer = le32(singleton);
    if (pointer < 0x20b000 || pointer > 0x210000 - sizeof(object) || (pointer & 3)) return false;
    read_error = "readFailure";
    if (!memory_read(device,pointer,32,object) || !memory_read(device,0x206794,28,vtable)) return false;
    read_error = "unsupported";
    if (le32(object) != 0x206794 || le32(object+12) || le32(object+16) || object[20] != 10 || object[21] ||
        memcmp(object+4,"\x70\x71\x72\x73\x74\x75",6)) return false;
    for (unsigned i = 0; i < 7; i++) if (le32(vtable+i*4) != supported_vtable[i]) return false;
    if (object[30]) { read_error = "busy"; return false; }
    read_error = "readFailure";
    if (!memory_read(device,0x20a359,1,live) || !memory_read(device,0xff007eb0,32,before)) return false;
    if (!valid_sleep(*live) || before[15] != *live) { read_error = "verificationFailed"; return false; }
    return true;
}
static int acquire_lock(void) {
    struct passwd *account = getpwuid(getuid());
    if (!account || !account->pw_dir) return -1;
    char directory[4096], path[4096]; struct stat info;
    int length = snprintf(directory,sizeof(directory),"%s/Library/Application Support/KeychronMenu",account->pw_dir);
    if (length < 0 || (size_t)length >= sizeof(directory)) return -1;
    if (mkdir(directory,0700) && errno != EEXIST) return -1;
    if (lstat(directory,&info) || !S_ISDIR(info.st_mode) || info.st_uid != getuid()) return -1;
    if (chmod(directory,0700)) return -1;
    length = snprintf(path,sizeof(path),"%s/sleep-control.lock",directory);
    if (length < 0 || (size_t)length >= sizeof(path)) return -1;
    int descriptor = open(path,O_CREAT|O_RDWR|O_NOFOLLOW|O_CLOEXEC,0600);
    if (descriptor < 0) return -1;
    if (fstat(descriptor,&info) || !S_ISREG(info.st_mode) || info.st_uid != getuid() || info.st_nlink != 1) { close(descriptor); return -1; }
    if (flock(descriptor,LOCK_EX|LOCK_NB)) { close(descriptor); return -2; }
    return descriptor;
}
#ifndef SLEEPCONTROL_TEST
int main(int argc, char **argv) {
    if (argc != 2 || (strcmp(argv[1],"read") && strcmp(argv[1],"on") && strcmp(argv[1],"off"))) { finish("unsupported",0); return 0; }
    signal(SIGALRM,timeout_handler); alarm(34);
    int lock = acquire_lock();
    if (lock < 0) { alarm(0); finish(lock == -2 ? "busy" : "readFailure",0); return 0; }
    Connection connection = {0}; CFStringRef serial = NULL; uint8_t live = 0, before[32], after[32];
    const char *status = connect_device(&connection);
    if (status) goto done;
    read_error = "readFailure";
    if (!version_query(connection.device)) { status = read_error; goto done; }
    if (!strcmp(argv[1],"read")) {
        uint8_t code[sizeof(toggle_code)];
        if (!memory_read(connection.device,0x207b88,sizeof(code),code)) status = read_error;
        else if (memcmp(code,toggle_code,sizeof(code))) status = "unsupported";
        else if (!memory_read(connection.device,0x20a359,1,&live)) status = read_error;
        else status = valid_sleep(live) ? "fresh" : "unsupported";
        goto done;
    }
    if (!write_guards(connection.device,&live,before)) { status = read_error; goto done; }
    uint8_t desired = !strcmp(argv[1],"on") ? 0x55 : 0xaa;
    if (live == desired) { status = "fresh"; goto done; }
    /* From this point an uncertain outcome is never retried automatically. */
    CFTypeRef serial_property = IOHIDDeviceGetProperty(connection.device,CFSTR(kIOHIDSerialNumberKey));
    if (!serial_property || CFGetTypeID(serial_property) != CFStringGetTypeID() || CFStringGetLength(serial_property) == 0) {
        status = "unsupported"; goto done;
    }
    serial = CFStringCreateCopy(NULL,serial_property);
    if (!serial) { status = "readFailure"; goto done; }
    mutation_started = 1; status = "verificationFailed";
    uint8_t enable[] = {0x70};
    if (!feature(connection.device,enable,sizeof(enable))) goto done;
    uint8_t write_setting[] = {0x74,0xbf,0x7e,0,0,1,0,desired,0};
    for (unsigned i = 0; i < sizeof(write_setting)-1; i++) write_setting[8] -= write_setting[i];
    if (!feature(connection.device,write_setting,sizeof(write_setting)) ||
        !memory_read(connection.device,0xff007eb0,32,after) || !valid_neighbors(before,after,desired)) goto done;
    uint8_t restart[] = {0x75,0,0,0,0,0,0,0x8b};
    (void)feature(connection.device,restart,sizeof(restart));
    disconnect_device(&connection);
    /* Restart can drop its own acknowledgement. Only fresh readback proves success. */
    double end = CFAbsoluteTimeGetCurrent() + 23;
    CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.6,false);
    while (CFAbsoluteTimeGetCurrent() < end) {
        const char *reconnect_status = connect_device(&connection);
        read_error = "readFailure";
        CFTypeRef reconnected_serial = connection.device ? IOHIDDeviceGetProperty(connection.device,CFSTR(kIOHIDSerialNumberKey)) : NULL;
        if (!reconnect_status && (!reconnected_serial || !CFEqual(serial,reconnected_serial))) break;
        if (!reconnect_status && version_query(connection.device) &&
            memory_read(connection.device,0x20a359,1,&live) && live == desired &&
            memory_read(connection.device,0xff007eb0,32,after) && valid_neighbors(before,after,desired)) {
            status = "fresh"; break;
        }
        if (reconnect_status && (!strcmp(reconnect_status,"ambiguous") || !strcmp(reconnect_status,"unsupported"))) break;
        disconnect_device(&connection);
        CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.3,false);
    }
done:
    disconnect_device(&connection); if (serial) CFRelease(serial); close(lock); alarm(0); finish(status,live); return 0;
}
#endif
