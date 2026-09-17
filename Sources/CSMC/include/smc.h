// Calma — minimal SMC access layer.
//
// The structure layout below mirrors the publicly documented AppleSMC user-client
// interface (as used by smcFanControl, iStats, and many other open-source tools).
// It is kept in C so the memory layout is guaranteed to match the kernel's.

#ifndef CALMA_SMC_H
#define CALMA_SMC_H

#include <IOKit/IOKitLib.h>
#include <stdint.h>

#define CALMA_SMC_MAX_BYTES 32

typedef struct {
    uint32_t size;       // payload size in bytes
    uint32_t type;       // four-char data type, e.g. 'ui8 ', 'flt ', 'hex_'
    uint8_t  bytes[CALMA_SMC_MAX_BYTES];
} calma_smc_value;

/// Opens a connection to the AppleSMC service. Returns KERN_SUCCESS on success.
kern_return_t calma_smc_open(io_connect_t *connection);

/// Closes a connection opened with calma_smc_open.
void calma_smc_close(io_connect_t connection);

/// Reads a key. Reading works without root on both Apple Silicon and Intel.
kern_return_t calma_smc_read(io_connect_t connection, const char *key, calma_smc_value *out);

/// Writes a key. Requires root. `value->size` must equal the key's declared size.
kern_return_t calma_smc_write(io_connect_t connection, const char *key, const calma_smc_value *value);

/// Returns the four-character key name at `index` (0 ..< value of `#KEY`).
kern_return_t calma_smc_key_at_index(io_connect_t connection, uint32_t index, char out[5]);

#endif
