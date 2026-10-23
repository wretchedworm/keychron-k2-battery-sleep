#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hid/IOHIDManager.h>
#include <stdio.h>
#include <stdlib.h>

static void failure(const char *reason) {
    printf("{\"version\":1,\"status\":\"%s\"}\n", reason);
}

int main(void) {
    IOHIDManagerRef manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    const void *keys[] = {CFSTR(kIOHIDProductKey), CFSTR(kIOHIDTransportKey)};
    const void *values[] = {CFSTR("Keychron K2"), CFSTR("Bluetooth")};
    CFDictionaryRef match = CFDictionaryCreate(kCFAllocatorDefault, keys, values, 2,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    IOHIDManagerSetDeviceMatching(manager, match);
    CFRelease(match);
    if (IOHIDManagerOpen(manager, kIOHIDOptionsTypeNone) != kIOReturnSuccess) {
        failure("accessDenied"); CFRelease(manager); return 0;
    }
    CFSetRef devices = IOHIDManagerCopyDevices(manager);
    CFIndex count = devices ? CFSetGetCount(devices) : 0;
    const void **list = calloc(count > 0 ? (size_t)count : 1, sizeof(void *));
    if (!list) { failure("readFailure"); goto cleanup; }
    if (devices) CFSetGetValues(devices, list);
    IOHIDDeviceRef selected = NULL;
    unsigned candidates = 0;
    for (CFIndex i = 0; i < count; i++) {
        IOHIDDeviceRef device = (IOHIDDeviceRef)list[i];
        CFArrayRef elements = IOHIDDeviceCopyMatchingElements(device, NULL, kIOHIDOptionsTypeNone);
        if (!elements) continue;
        for (CFIndex j = 0; j < CFArrayGetCount(elements); j++) {
            IOHIDElementRef element = (IOHIDElementRef)CFArrayGetValueAtIndex(elements, j);
            if (IOHIDElementGetUsagePage(element) == 6 && IOHIDElementGetUsage(element) == 0x20 &&
                IOHIDElementGetReportID(element) == 3 && IOHIDElementGetLogicalMin(element) == 0 &&
                IOHIDElementGetLogicalMax(element) == 100 &&
                IOHIDElementGetType(element) == kIOHIDElementTypeInput_Misc) {
                selected = device; candidates++; break;
            }
        }
        CFRelease(elements);
    }
    if (candidates > 1) failure("ambiguous");
    else if (!selected) failure(count ? "unsupported" : "disconnected");
    else {
        unsigned char bytes[2] = {0};
        CFIndex length = sizeof(bytes);
        IOReturn result = IOHIDDeviceGetReport(selected, kIOHIDReportTypeInput, 3, bytes, &length);
        if (result != kIOReturnSuccess) failure(result == kIOReturnNotPermitted ? "accessDenied" : "readFailure");
        else if (length != 2 || bytes[0] != 3 || bytes[1] > 100) failure("invalidReport");
        else printf("{\"version\":1,\"status\":\"fresh\",\"percent\":%u}\n", bytes[1]);
    }
    free(list);
cleanup:
    if (devices) CFRelease(devices);
    IOHIDManagerClose(manager, kIOHIDOptionsTypeNone);
    CFRelease(manager);
    return 0;
}
