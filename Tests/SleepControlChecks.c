#define SLEEPCONTROL_TEST
#include "../Sources/SleepControl.c"
#include <assert.h>

int main(void) {
    uint8_t version[sizeof(supported_version)];
    memcpy(version,supported_version,sizeof(version));
    assert(valid_version(version,sizeof(version)));
    version[2] = 9;
    assert(!valid_version(version,sizeof(version)));
    memcpy(version,supported_version,sizeof(version)); version[13] = '1';
    assert(!valid_version(version,sizeof(version)));
    assert(!valid_version(supported_version,13));

    uint8_t response[9] = {0x72,0x59,0xa3,0x20,0,1,0,0xaa,0};
    for (unsigned i = 0; i < 8; i++) response[8] -= response[i];
    assert(valid_memory_response(response,sizeof(response),0x20a359,1));
    assert(!valid_memory_response(response,sizeof(response)-1,0x20a359,1));
    assert(!valid_memory_response(response,sizeof(response),0x20a358,1));
    response[7] ^= 1;
    assert(!valid_memory_response(response,sizeof(response),0x20a359,1));

    uint8_t before[32], after[32];
    for (unsigned i = 0; i < 32; i++) before[i] = (uint8_t)(i*7);
    before[15] = 0xaa; memcpy(after,before,32); after[15] = 0x55;
    assert(valid_neighbors(before,after,0x55));
    assert(!valid_neighbors(before,after,0xaa));
    for (unsigned i = 0; i < 32; i++) {
        if (i == 15) continue;
        after[i] ^= 1; assert(!valid_neighbors(before,after,0x55)); after[i] ^= 1;
    }
    assert(valid_sleep(0xaa) && valid_sleep(0x55) && !valid_sleep(0));
    /* Fingerprints start at the function entry, not at the load's TLV header. */
    assert(toggle_code[0] == 0x10 && toggle_code[1] == 0xb5);
    assert(dispatcher_code[0] == 0x7c && dispatcher_code[1] == 0xb5);
    puts("SleepControl protocol checks passed");
    return 0;
}
