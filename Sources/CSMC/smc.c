#include "smc.h"
#include <string.h>

#define KERNEL_INDEX_SMC   2
#define SMC_CMD_READ_BYTES 5
#define SMC_CMD_WRITE_BYTES 6
#define SMC_CMD_READ_KEYINFO 9

typedef struct {
    char major;
    char minor;
    char build;
    char reserved[1];
    uint16_t release;
} SMCKeyData_vers_t;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMCKeyData_pLimitData_t;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    char dataAttributes;
} SMCKeyData_keyInfo_t;

typedef struct {
    uint32_t key;
    SMCKeyData_vers_t vers;
    SMCKeyData_pLimitData_t pLimitData;
    SMCKeyData_keyInfo_t keyInfo;
    char result;
    char status;
    char data8;
    uint32_t data32;
    uint8_t bytes[CALMA_SMC_MAX_BYTES];
} SMCKeyData_t;

static uint32_t fourcc(const char *key) {
    return ((uint32_t)(uint8_t)key[0] << 24) |
           ((uint32_t)(uint8_t)key[1] << 16) |
           ((uint32_t)(uint8_t)key[2] << 8)  |
           ((uint32_t)(uint8_t)key[3]);
}

static kern_return_t call(io_connect_t connection, SMCKeyData_t *input, SMCKeyData_t *output) {
    size_t outSize = sizeof(SMCKeyData_t);
    return IOConnectCallStructMethod(connection, KERNEL_INDEX_SMC,
                                     input, sizeof(SMCKeyData_t),
                                     output, &outSize);
}

kern_return_t calma_smc_open(io_connect_t *connection) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (service == 0) {
        return KERN_FAILURE;
    }
    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, connection);
    IOObjectRelease(service);
    return result;
}

void calma_smc_close(io_connect_t connection) {
    IOServiceClose(connection);
}

static kern_return_t key_info(io_connect_t connection, const char *key, SMCKeyData_keyInfo_t *info) {
    SMCKeyData_t input;
    SMCKeyData_t output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.key = fourcc(key);
    input.data8 = SMC_CMD_READ_KEYINFO;
    kern_return_t result = call(connection, &input, &output);
    if (result != KERN_SUCCESS) return result;
    if (output.result != 0) return KERN_INVALID_ARGUMENT; // key does not exist on this model
    *info = output.keyInfo;
    return KERN_SUCCESS;
}

kern_return_t calma_smc_read(io_connect_t connection, const char *key, calma_smc_value *out) {
    if (key == NULL || strlen(key) != 4 || out == NULL) return KERN_INVALID_ARGUMENT;
    memset(out, 0, sizeof(*out));

    SMCKeyData_keyInfo_t info;
    kern_return_t result = key_info(connection, key, &info);
    if (result != KERN_SUCCESS) return result;
    if (info.dataSize > CALMA_SMC_MAX_BYTES) return KERN_INVALID_ARGUMENT;

    SMCKeyData_t input;
    SMCKeyData_t output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.key = fourcc(key);
    input.keyInfo.dataSize = info.dataSize;
    input.data8 = SMC_CMD_READ_BYTES;

    result = call(connection, &input, &output);
    if (result != KERN_SUCCESS) return result;
    if (output.result != 0) return KERN_FAILURE;

    out->size = info.dataSize;
    out->type = info.dataType;
    memcpy(out->bytes, output.bytes, info.dataSize);
    return KERN_SUCCESS;
}

kern_return_t calma_smc_write(io_connect_t connection, const char *key, const calma_smc_value *value) {
    if (key == NULL || strlen(key) != 4 || value == NULL) return KERN_INVALID_ARGUMENT;

    SMCKeyData_keyInfo_t info;
    kern_return_t result = key_info(connection, key, &info);
    if (result != KERN_SUCCESS) return result;
    // Refuse size mismatches: writing the wrong width is how machines get into odd states.
    if (info.dataSize != value->size || value->size > CALMA_SMC_MAX_BYTES) return KERN_INVALID_ARGUMENT;

    SMCKeyData_t input;
    SMCKeyData_t output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.key = fourcc(key);
    input.data8 = SMC_CMD_WRITE_BYTES;
    input.keyInfo.dataSize = value->size;
    memcpy(input.bytes, value->bytes, value->size);

    result = call(connection, &input, &output);
    if (result != KERN_SUCCESS) return result;
    if (output.result != 0) return KERN_FAILURE;
    return KERN_SUCCESS;
}

kern_return_t calma_smc_key_at_index(io_connect_t connection, uint32_t index, char out[5]) {
    SMCKeyData_t input;
    SMCKeyData_t output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.data8 = 8; // kSMCGetKeyFromIndex
    input.data32 = index;
    kern_return_t result = call(connection, &input, &output);
    if (result != KERN_SUCCESS) return result;
    out[0] = (char)(output.key >> 24); out[1] = (char)(output.key >> 16);
    out[2] = (char)(output.key >> 8);  out[3] = (char)output.key; out[4] = 0;
    return KERN_SUCCESS;
}
